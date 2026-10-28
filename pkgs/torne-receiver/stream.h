#ifndef TORNE_STREAM_H
#define TORNE_STREAM_H

#include <libusb-1.0/libusb.h>
#include <stdint.h>

struct torne_stream;

int torne_stream_start(struct torne_stream **stream, libusb_context *context,
                       libusb_device_handle *usb, int fd, uint32_t tsid);
void torne_stream_stop(struct torne_stream *stream);
int torne_stream_error(struct torne_stream *stream);

#endif
