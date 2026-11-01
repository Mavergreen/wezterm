use core_foundation::base::TCFType;
use core_foundation_sys::base::{Boolean, OSStatus};
use security_framework::certificate::SecCertificate;
use security_framework::secure_transport::{
    ClientBuilder, ClientHandshakeError, SslConnectionType, SslContext, SslProtocol,
    SslProtocolSide,
};
use security_framework_sys::secure_transport::SSLContextRef;
use std::io::{BufRead, BufReader, Read};
use std::net::{SocketAddr, TcpStream};
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::OnceLock;
use std::time::Duration;

mod tickets {
    include!(concat!(env!("TLS_CRATE_DIR"), "/src/session_tickets.rs"));
}

const _: tickets::SessionTicketsFn =
    security_framework_sys::secure_transport::SSLSetSessionTicketsEnabled;
static CALLS: AtomicUsize = AtomicUsize::new(0);
static CONTEXT: AtomicUsize = AtomicUsize::new(0);
static FLAG: AtomicUsize = AtomicUsize::new(0);
static STATUS: AtomicUsize = AtomicUsize::new(0);

unsafe extern "C" fn native_spy(ctx: SSLContextRef, enabled: Boolean) -> OSStatus {
    CALLS.fetch_add(1, Ordering::SeqCst);
    CONTEXT.store(ctx as usize, Ordering::SeqCst);
    FLAG.store(enabled as usize, Ordering::SeqCst);
    STATUS.load(Ordering::SeqCst) as OSStatus
}

fn context() -> SslContext {
    SslContext::new(SslProtocolSide::CLIENT, SslConnectionType::STREAM).unwrap()
}

#[test]
fn absent_symbol_returns_unimplemented_for_both_explicit_values() {
    let ctx = context();
    for enabled in [0, 1] {
        assert_eq!(
            unsafe { tickets::set_with(ctx.as_concrete_TypeRef(), enabled, None) },
            -4
        );
    }
}

#[test]
fn present_symbol_receives_original_context_and_boolean_once_and_preserves_errors() {
    let ctx = context();
    for (enabled, status) in [(0, 0), (1, -50), (0, -9800)] {
        CALLS.store(0, Ordering::SeqCst);
        STATUS.store(status as usize, Ordering::SeqCst);
        assert_eq!(
            unsafe { tickets::set_with(ctx.as_concrete_TypeRef(), enabled, Some(native_spy)) },
            status
        );
        assert_eq!(CALLS.load(Ordering::SeqCst), 1);
        assert_eq!(
            CONTEXT.load(Ordering::SeqCst),
            ctx.as_concrete_TypeRef() as usize
        );
        assert_eq!(FLAG.load(Ordering::SeqCst), enabled as usize);
    }
}

#[test]
fn resolution_is_cached_including_an_absent_symbol() {
    for present in [false, true] {
        let cache = OnceLock::new();
        let calls = AtomicUsize::new(0);
        for _ in 0..2 {
            let resolved = tickets::resolve_with(&cache, || {
                calls.fetch_add(1, Ordering::SeqCst);
                if present {
                    Some(native_spy as tickets::SessionTicketsFn)
                } else {
                    None
                }
            });
            assert_eq!(resolved.is_some(), present);
        }
        assert_eq!(calls.load(Ordering::SeqCst), 1);
    }
}

#[test]
fn actual_mavericks_api_reports_unsupported_instead_of_fake_success() {
    assert!(
        tickets::resolve().is_none(),
        "native 10.9 must not acquire a replacement API stub"
    );
    let mut ctx = context();
    for enabled in [false, true] {
        assert_eq!(
            ctx.set_session_tickets_enabled(enabled).unwrap_err().code(),
            -4
        );
    }
}

struct Server(Child);
impl Drop for Server {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

fn connection() -> (Server, TcpStream) {
    let dir = std::env::var("TLS_FIXTURE_DIR").unwrap();
    let child = Command::new(std::env::var("TLS_SERVER").unwrap())
        .arg(format!("{dir}/server.pem"))
        .arg(format!("{dir}/server.key"))
        .env("OPENSSL_CONF", "/dev/null")
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn()
        .unwrap();
    let mut server = Server(child);
    let mut line = String::new();
    BufReader::new(server.0.stdout.take().unwrap())
        .read_line(&mut line)
        .unwrap();
    let addr: SocketAddr = format!("127.0.0.1:{}", line.trim().parse::<u16>().unwrap())
        .parse()
        .unwrap();
    let stream = TcpStream::connect_timeout(&addr, Duration::from_secs(5)).unwrap();
    stream
        .set_read_timeout(Some(Duration::from_secs(5)))
        .unwrap();
    stream
        .set_write_timeout(Some(Duration::from_secs(5)))
        .unwrap();
    (server, stream)
}

fn builder(anchored: bool) -> ClientBuilder {
    let mut builder = ClientBuilder::new();
    builder
        .protocol_min(SslProtocol::TLS12)
        .protocol_max(SslProtocol::TLS12);
    if anchored {
        let root = std::fs::read(format!(
            "{}/ca.der",
            std::env::var("TLS_FIXTURE_DIR").unwrap()
        ))
        .unwrap();
        builder.anchor_certificates(&[SecCertificate::from_der(&root).unwrap()]);
    }
    builder.trust_anchor_certificates_only(true);
    builder
}

#[test]
fn default_tickets_stay_disabled_and_local_trust_sni_server_auth_and_protocols_work() {
    let (_server, stream) = connection();
    let mut stream = builder(true).handshake("localhost", stream).unwrap();
    assert_eq!(stream.context().peer_domain_name().unwrap(), "localhost");
    assert!(stream.context().break_on_server_auth().unwrap());
    assert_eq!(
        stream.context().protocol_version_min().unwrap(),
        SslProtocol::TLS12
    );
    assert_eq!(
        stream.context().protocol_version_max().unwrap(),
        SslProtocol::TLS12
    );
    assert_eq!(
        stream.context().negotiated_protocol_version().unwrap(),
        SslProtocol::TLS12
    );
    let expected = b"TLS_FIXTURE_OK localhost\n";
    let mut actual = vec![0; expected.len()];
    stream.read_exact(&mut actual).unwrap();
    assert_eq!(actual, expected);
}

fn must_reject(anchored: bool, domain: &str) {
    let (_server, stream) = connection();
    match builder(anchored).handshake(domain, stream) {
        Err(ClientHandshakeError::Failure(error)) => {
            assert_ne!(error.code(), security_framework_sys::base::errSecIO);
            assert_ne!(
                error.code(),
                security_framework_sys::base::errSecUnimplemented
            );
            println!("rejected anchored={anchored} domain={domain}: {error:?}");
        }
        other => panic!(
            "certificate policy did not reject anchored={anchored} domain={domain}: {other:?}"
        ),
    }
}

#[test]
fn untrusted_local_ca_is_rejected_without_keychain_changes() {
    must_reject(false, "localhost");
}

#[test]
fn trusted_ca_does_not_disable_hostname_validation() {
    must_reject(true, "wrong.invalid");
}
