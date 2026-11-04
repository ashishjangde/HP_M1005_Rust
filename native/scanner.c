/* Native macOS scanner transport and image export. GPL-2.0-or-later. */
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/usb/IOUSBLib.h>
#include <CoreGraphics/CoreGraphics.h>
#include <ImageIO/ImageIO.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

struct hp_usb {
    IOUSBInterfaceInterface300 **interface;
    UInt8 input, output;
};

static int property(io_service_t service, CFStringRef key) {
    CFTypeRef value = IORegistryEntrySearchCFProperty(service, kIOServicePlane, key,
        kCFAllocatorDefault, kIORegistryIterateRecursively | kIORegistryIterateParents);
    int result = -1;
    if (value) {
        if (CFGetTypeID(value) == CFNumberGetTypeID())
            CFNumberGetValue(value, kCFNumberIntType, &result);
        CFRelease(value);
    }
    return result;
}

void *hp_scanner_open(uint32_t *error) {
    io_iterator_t iterator = 0;
    *error = IOServiceGetMatchingServices(kIOMainPortDefault,
        IOServiceMatching("IOUSBHostInterface"), &iterator);
    if (*error != kIOReturnSuccess) return NULL;
    io_service_t service;
    struct hp_usb *handle = NULL;
    *error = kIOReturnNotFound;
    while ((service = IOIteratorNext(iterator))) {
        if (property(service, CFSTR("idVendor")) != 0x03f0 ||
            property(service, CFSTR("idProduct")) != 0x3b17 ||
            property(service, CFSTR("bInterfaceNumber")) != 0) {
            IOObjectRelease(service);
            continue;
        }
        IOCFPlugInInterface **plugin = NULL;
        SInt32 score;
        *error = IOCreatePlugInInterfaceForService(service, kIOUSBInterfaceUserClientTypeID,
            kIOCFPlugInInterfaceID, &plugin, &score);
        IOObjectRelease(service);
        if (*error || !plugin) break;
        IOUSBInterfaceInterface300 **interface = NULL;
        HRESULT query = (*plugin)->QueryInterface(plugin,
            CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID300), (LPVOID *)&interface);
        (*plugin)->Release(plugin);
        if (query || !interface) { *error = kIOReturnUnsupported; break; }
        *error = (*interface)->USBInterfaceOpen(interface);
        if (*error) { (*interface)->Release(interface); break; }
        UInt8 endpoints = 0, input = 0, output = 0;
        *error = (*interface)->GetNumEndpoints(interface, &endpoints);
        if (!*error) {
            for (UInt8 pipe = 1; pipe <= endpoints; pipe++) {
                UInt8 direction, number, type, interval;
                UInt16 packet;
                if ((*interface)->GetPipeProperties(interface, pipe, &direction, &number,
                    &type, &packet, &interval) == kIOReturnSuccess && type == kUSBBulk) {
                    if (direction == kUSBIn) input = pipe;
                    if (direction == kUSBOut) output = pipe;
                }
            }
        }
        if (input && output) {
            handle = calloc(1, sizeof(*handle));
            if (handle) {
                handle->interface = interface;
                handle->input = input;
                handle->output = output;
                *error = 0;
                break;
            }
            *error = kIOReturnNoMemory;
        } else if (!*error) *error = kIOReturnNotFound;
        (*interface)->USBInterfaceClose(interface);
        (*interface)->Release(interface);
        break;
    }
    IOObjectRelease(iterator);
    return handle;
}

uint32_t hp_scanner_read(void *context, unsigned char *data, uint32_t *length) {
    struct hp_usb *h = context;
    return (*h->interface)->ReadPipeTO(h->interface, h->input, data, length, 30000, 30000);
}

uint32_t hp_scanner_write(void *context, const unsigned char *data, uint32_t length) {
    struct hp_usb *h = context;
    return (*h->interface)->WritePipeTO(h->interface, h->output, (void *)data, length, 30000, 30000);
}

void hp_scanner_close(void *context) {
    struct hp_usb *h = context;
    (*h->interface)->USBInterfaceClose(h->interface);
    (*h->interface)->Release(h->interface);
    free(h);
}

/* No framework retains the Rust buffer after this synchronous function returns. */
int hp_scanner_save(const unsigned char *pixels, uint32_t width, uint32_t height,
                    uint32_t channels, uint32_t dpi, const char *path, int pdf) {
    CGColorSpaceRef color = channels == 3 ? CGColorSpaceCreateDeviceRGB() : CGColorSpaceCreateDeviceGray();
    CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, pixels,
        (size_t)width * height * channels, NULL);
    if (!color || !provider) {
        if (color) CGColorSpaceRelease(color);
        if (provider) CGDataProviderRelease(provider);
        return -1;
    }
    CGImageRef image = CGImageCreate(width, height, 8, channels * 8, width * channels,
        color, kCGImageAlphaNone, provider, NULL, false, kCGRenderingIntentDefault);
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(color);
    if (!image) return -1;
    CFURLRef url = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)path, strlen(path), false);
    if (!url) { CGImageRelease(image); return -1; }
    int result = -1;
    if (pdf) {
        CGRect page = CGRectMake(0, 0, (double)width * 72 / dpi, (double)height * 72 / dpi);
        CGContextRef context = CGPDFContextCreateWithURL(url, &page, NULL);
        if (context) {
            CGPDFContextBeginPage(context, NULL);
            CGContextDrawImage(context, page, image);
            CGPDFContextEndPage(context);
            CGPDFContextClose(context);
            CGContextRelease(context);
            result = 0;
        }
    } else {
        CGImageDestinationRef destination = CGImageDestinationCreateWithURL(url, CFSTR("public.png"), 1, NULL);
        if (destination) {
            double resolution = dpi;
            CFNumberRef number = CFNumberCreate(NULL, kCFNumberDoubleType, &resolution);
            const void *keys[] = {kCGImagePropertyDPIWidth, kCGImagePropertyDPIHeight};
            const void *values[] = {number, number};
            CFDictionaryRef options = CFDictionaryCreate(NULL, keys, values, 2,
                &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
            CGImageDestinationAddImage(destination, image, options);
            result = CGImageDestinationFinalize(destination) ? 0 : -1;
            CFRelease(options);
            CFRelease(number);
            CFRelease(destination);
        }
    }
    CFRelease(url);
    CGImageRelease(image);
    return result;
}
