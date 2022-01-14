/* 
 * @author joelai
 */

#include "priv.h"

size_t aloe_fb_read(aloe_fb_t *fb, void *data, size_t sz) {
	size_t rw_sz, ret_sz;

	if (sz > fb->lmt) sz = fb->lmt;
	ret_sz = sz;

	// rinbuf max continuous readable size: min(lmt, (cap - pos))
	while ((rw_sz = aloe_min(sz, fb->cap - fb->pos)) > 0) {
		memcpy(data, (char*)fb->data + fb->pos, rw_sz);
		fb->pos = (fb->pos + rw_sz) % fb->cap;
		fb->lmt -= rw_sz;
		if (rw_sz >= sz) break;
		sz -= rw_sz;
		data = (char*)data + rw_sz;
	}
	return ret_sz;
}

size_t aloe_fb_write(aloe_fb_t *fb, const void *data, size_t sz) {
	size_t rw_sz, ret_sz;

	ret_sz = aloe_min(sz, fb->cap - fb->lmt);

	// rinbuf max continuous writable position: wpos = ((pos + lmt) % cap)
	while ((rw_sz = aloe_min(sz, fb->cap - fb->lmt)) > 0) {
		int rw_pos = (fb->pos + fb->lmt) % fb->cap;
		if (rw_sz > fb->cap - rw_pos) rw_sz = fb->cap - rw_pos;
		memcpy((char*)fb->data + rw_pos, data, rw_sz);
		fb->lmt += rw_sz;
		if (rw_sz >= sz) break;
		sz -= rw_sz;
		data = (char*)data + rw_sz;
	}
	return ret_sz;
}

int aloe_fb_expand(aloe_fb_t *fb, size_t cap, int retain) {
	void *data;

	if (cap <= 0 || fb->cap >= cap) return 0;
	if (!(data = malloc(cap))) return ENOMEM;
	if (fb->data) {
		if (retain && fb->lmt > 0) {
			aloe_fb_read(fb, data, fb->lmt);
			fb->pos = 0;
		}
		free(fb->data);
	}
	fb->data = data;
	fb->cap = cap;
	return 0;
}

int aloe_vaprintf(aloe_fb_t *buf, ssize_t max, const char *fmt, va_list va) {
	int r;

	buf->lmt = buf->pos = 0;
	if (!fmt || !fmt[0]) return 0;

	if (max == 0) {
		r = vsnprintf((char*)buf->data, buf->cap, fmt, va);
		if (r < 0 || r >= buf->cap) return -1;
		buf->lmt = r;
		return r;
	}

	if (aloe_fb_expand(buf, ((max > 0 && max < 32) ? max : 32), 0) != 0) {
		return -1;
	}
	while (1) {
		va_list vb;

#if __STDC_VERSION__ < 199901L
#  warning "va_copy() may require C99"
#endif
		va_copy(vb, va);
		r = vsnprintf((char*)buf->data, buf->cap, fmt, vb);
		if (r < 0 || r >= buf->cap) {
			if (max > 0 && buf->cap >= max) return -1;
			r = buf->cap * 2;
			if (max > 0 && r > max) r = max;
			if (aloe_fb_expand(buf, r, 0) != 0) {
				va_end(vb);
				return -1;
			}
			va_end(vb);
			continue;
		}
		buf->lmt = r;
		va_end(vb);
		return r;
	};
}

int aloe_aprintf(aloe_fb_t *buf, ssize_t max, const char *fmt, ...) {
	int r;
	va_list va;

	if (!fmt) return 0;
	va_start(va, fmt);
	r = aloe_vaprintf(buf, max, fmt, va);
	va_end(va);
	return r;
}
