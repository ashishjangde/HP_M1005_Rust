/* GPL-2.0-or-later. Narrow ABI around macOS CUPS and the bundled JBIG codec. */
#include <cups/raster.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "jbig.h"

typedef void (*output_callback)(unsigned char *, size_t, void *);

void hp_jbig_encode(uint32_t width, uint32_t height, unsigned char *bitmap,
                    output_callback output, void *context) {
    struct jbg_enc_state state;
    unsigned char *planes[] = { bitmap };
    jbg_enc_init(&state, width, height, 1, planes, output, context);
    jbg_enc_options(&state, JBG_ILEAVE | JBG_SMID,
        JBG_DELAY_AT | JBG_LRLTWO | JBG_TPDON | JBG_TPBON | JBG_DPON, 128, 0, 0);
    jbg_enc_out(&state);
    jbg_enc_free(&state);
}

/* Used to verify the Rust framing and input conversion against a real decoder. */
int hp_jbig_decode(unsigned char *data, size_t length, unsigned char *output,
                   size_t capacity, uint32_t *width, uint32_t *height) {
    struct jbg_dec_state state;
    size_t consumed;
    jbg_dec_init(&state);
    jbg_dec_maxsize(&state, 16384, 16384);
    int result = jbg_dec_in(&state, data, length, &consumed);
    if (result == JBG_EOK && consumed == length && jbg_dec_getsize(&state) <= capacity) {
        *width = (uint32_t)jbg_dec_getwidth(&state);
        *height = (uint32_t)jbg_dec_getheight(&state);
        memcpy(output, jbg_dec_getimage(&state, 0), jbg_dec_getsize(&state));
    } else {
        result = -1;
    }
    jbg_dec_free(&state);
    return result;
}

/* Keep the platform-dependent cups_page_header2_t layout out of Rust. */
struct hp_raster {
    cups_raster_t *stream;
    cups_page_header2_t header;
};

struct hp_page_info {
    uint32_t width, height, bytes_per_line, bits_per_color, bits_per_pixel;
    uint32_t color_space, color_order, x_dpi, y_dpi, copies, page_width, page_height;
};

void *hp_raster_open(int descriptor) {
    struct hp_raster *r = calloc(1, sizeof(*r));
    if (!r) return NULL;
    r->stream = cupsRasterOpen(descriptor, CUPS_RASTER_READ);
    if (!r->stream) { free(r); return NULL; }
    return r;
}

int hp_raster_header(void *context, struct hp_page_info *out) {
    struct hp_raster *r = context;
    if (!cupsRasterReadHeader2(r->stream, &r->header)) return 0;
    cups_page_header2_t *h = &r->header;
    *out = (struct hp_page_info){h->cupsWidth, h->cupsHeight, h->cupsBytesPerLine,
        h->cupsBitsPerColor, h->cupsBitsPerPixel, h->cupsColorSpace, h->cupsColorOrder,
        h->HWResolution[0], h->HWResolution[1], h->NumCopies, h->PageSize[0], h->PageSize[1]};
    return 1;
}

uint32_t hp_raster_pixels(void *context, unsigned char *buffer, uint32_t count) {
    return cupsRasterReadPixels(((struct hp_raster *)context)->stream, buffer, count);
}

void hp_raster_close(void *context) {
    struct hp_raster *r = context;
    cupsRasterClose(r->stream);
    free(r);
}
