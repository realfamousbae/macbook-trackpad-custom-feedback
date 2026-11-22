#include "Trackpad.h"
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <stddef.h>

// Private contact layout documented in mactic/docs/implementation.md.
typedef struct {
    int32_t frame;
    double time;
    int32_t id;
    int32_t state;
    int32_t finger;
    int32_t hand;
    float positionAndVelocity[4];
    float size;
    float pressure;
    float geometry[9];
    float zPressure;
} Contact;

_Static_assert(sizeof(Contact) == 96, "Unexpected contact stride");
_Static_assert(offsetof(Contact, zPressure) == 92, "Unexpected pressure offset");

typedef void (*FrameCallback)(const void *, const Contact *, int, double, int);
typedef void (*RegisterCallback)(const void *, FrameCallback);
static RegisterCallback unregister_frame;
static void (*stop_device)(const void *);
static void *framework;
static CFArrayRef devices;
static const void *device;
static TrackpadFrameHandler deliver;

static void receive_frame(const void *source, const Contact *contacts,
                          int count, double time, int frame) {
    int active = 0;
    const Contact *single = NULL;
    for (int index = 0; index < count; index++) {
        const Contact *touch = &contacts[index];
        if (touch->state >= 3 && touch->state <= 6) {
            active++;
            single = touch;
        }
    }
    if (active == 1) {
        deliver(time, active, single->id, single->size, single->pressure, single->zPressure);
    } else {
        deliver(time, active, 0, 0, 0, 0);
    }
}

int trackpad_start(TrackpadFrameHandler handler) {
    if (device) return 0;
    if (!framework) {
        framework = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport",
                           RTLD_LAZY | RTLD_LOCAL);
    }
    if (!framework) return 1;

    CFArrayRef (*list)(void) = dlsym(framework, "MTDeviceCreateList");
    bool (*is_builtin)(const void *) = dlsym(framework, "MTDeviceIsBuiltIn");
    RegisterCallback register_frame = dlsym(framework, "MTRegisterContactFrameCallback");
    int (*start_device)(const void *, int) = dlsym(framework, "MTDeviceStart");
    unregister_frame = dlsym(framework, "MTUnregisterContactFrameCallback");
    stop_device = dlsym(framework, "MTDeviceStop");
    if (!list || !is_builtin || !register_frame || !start_device ||
        !unregister_frame || !stop_device) return 1;

    devices = list();
    if (!devices) return 2;
    for (CFIndex index = 0; index < CFArrayGetCount(devices); index++) {
        const void *candidate = CFArrayGetValueAtIndex(devices, index);
        if (is_builtin(candidate)) {
            device = candidate;
            break;
        }
    }
    if (!device) {
        CFRelease(devices);
        devices = NULL;
        return 2;
    }

    deliver = handler;
    register_frame(device, receive_frame);
    if (start_device(device, 0) != 0) {
        trackpad_stop();
        return 3;
    }
    return 0;
}

void trackpad_stop(void) {
    if (!device) return;
    unregister_frame(device, receive_frame);
    stop_device(device);
    CFRelease(devices);
    devices = NULL;
    device = NULL;
}
