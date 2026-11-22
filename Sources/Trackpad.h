#include <stdint.h>

typedef void (*TrackpadFrameHandler)(double time, int count, int32_t id,
                                     float size, float pressure, float zPressure);

int trackpad_start(TrackpadFrameHandler handler);
void trackpad_stop(void);
