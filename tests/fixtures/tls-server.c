#include <arpa/inet.h>
#include <netinet/in.h>
#include <openssl/err.h>
#include <openssl/ssl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/socket.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc != 3) return 2;
    signal(SIGPIPE, SIG_IGN);
    SSL_CTX *ctx = SSL_CTX_new(TLS_server_method());
    if (!ctx || !SSL_CTX_set_min_proto_version(ctx, TLS1_2_VERSION) ||
        !SSL_CTX_set_max_proto_version(ctx, TLS1_2_VERSION) ||
        SSL_CTX_use_certificate_chain_file(ctx, argv[1]) != 1 ||
        SSL_CTX_use_PrivateKey_file(ctx, argv[2], SSL_FILETYPE_PEM) != 1 ||
        SSL_CTX_check_private_key(ctx) != 1) {
        ERR_print_errors_fp(stderr);
        return 2;
    }
    int listener = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in addr = {0};
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    socklen_t len = sizeof(addr);
    if (listener < 0 || bind(listener, (struct sockaddr *)&addr, len) ||
        listen(listener, 1) || getsockname(listener, (struct sockaddr *)&addr, &len)) return 2;
    printf("%u\n", (unsigned)ntohs(addr.sin_port));
    fflush(stdout);
    int peer = accept(listener, NULL, NULL);
    if (peer < 0) return 2;
    SSL *ssl = SSL_new(ctx);
    SSL_set_fd(ssl, peer);
    int ok = SSL_accept(ssl) == 1;
    if (ok) {
        const char *sni = SSL_get_servername(ssl, TLSEXT_NAMETYPE_host_name);
        char reply[1024];
        int count = snprintf(reply, sizeof(reply), "TLS_FIXTURE_OK %s\n", sni ? sni : "NO_SNI");
        ok = count > 0 && count < sizeof(reply) && SSL_write(ssl, reply, count) == count;
    }
    if (!ok) ERR_print_errors_fp(stderr);
    SSL_free(ssl);
    close(peer);
    close(listener);
    SSL_CTX_free(ctx);
    return ok ? 0 : 1;
}
