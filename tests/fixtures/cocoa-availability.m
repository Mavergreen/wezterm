#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <stdio.h>

int main(void) {
    Class classes[] = {[NSApplication class], [NSWindow class], [NSWindow class], [NSWindow class]};
    const char *names[] = {"effectiveAppearance", "setTabbingMode:", "setTitleVisibility:", "setTitlebarAppearsTransparent:"};
    for (int i = 0; i < 4; ++i) {
        int present = class_getInstanceMethod(classes[i], sel_registerName(names[i])) != NULL;
        printf("%s %s %s\n", class_getName(classes[i]), names[i], present ? "present" : "absent");
        if (present) return 1;
    }
    return 0;
}
