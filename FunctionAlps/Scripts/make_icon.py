"""Compose the 1024x1024 App Store icon from webapp/public/brand/logo-mark.png.
Pure Python (no PIL): PNG decode (all filters, palette/RGB/RGBA/gray), alpha
bbox crop, box-sampled resize, composite on cream, PNG encode.
usage: make_icon.py SRC DST FILL_RATIO
"""
import struct, sys, zlib

def read_png(path):
    data = open(path, 'rb').read()
    assert data[:8] == b'\x89PNG\r\n\x1a\n'
    pos = 8; idat = []; plte = None; trns = None
    while pos < len(data):
        ln, typ = struct.unpack('>I4s', data[pos:pos+8]); body = data[pos+8:pos+8+ln]; pos += 12 + ln
        if typ == b'IHDR': w, h, bd, ct, _, _, il = struct.unpack('>IIBBBBB', body); assert bd == 8 and il == 0, (bd, il)
        elif typ == b'PLTE': plte = body
        elif typ == b'tRNS': trns = body
        elif typ == b'IDAT': idat.append(body)
        elif typ == b'IEND': break
    raw = zlib.decompress(b''.join(idat))
    ch = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ct]; stride = w * ch
    out = bytearray(); prev = bytearray(stride); p = 0
    for _ in range(h):
        f = raw[p]; line = bytearray(raw[p+1:p+1+stride]); p += 1 + stride
        if f == 1:
            for i in range(ch, stride): line[i] = (line[i] + line[i-ch]) & 255
        elif f == 2:
            for i in range(stride): line[i] = (line[i] + prev[i]) & 255
        elif f == 3:
            for i in range(stride): line[i] = (line[i] + ((line[i-ch] if i >= ch else 0) + prev[i]) // 2) & 255
        elif f == 4:
            for i in range(stride):
                a = line[i-ch] if i >= ch else 0; b = prev[i]; c = prev[i-ch] if i >= ch else 0
                pa = abs(b - c); pb = abs(a - c); pc = abs(a + b - 2*c)
                pr = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 255
        out += line; prev = line
    # normalise to RGBA rows
    px = bytearray(w * h * 4)
    if ct == 6: px[:] = out
    elif ct == 2:
        for i in range(w*h): px[4*i:4*i+3] = out[3*i:3*i+3]; px[4*i+3] = 255
    elif ct == 3:
        for i in range(w*h):
            k = out[i]; px[4*i:4*i+3] = plte[3*k:3*k+3]; px[4*i+3] = trns[k] if trns and k < len(trns) else 255
    elif ct == 0:
        for i in range(w*h): v = out[i]; px[4*i:4*i+3] = bytes((v, v, v)); px[4*i+3] = 255
    elif ct == 4:
        for i in range(w*h): v = out[2*i]; px[4*i:4*i+3] = bytes((v, v, v)); px[4*i+3] = out[2*i+1]
    return w, h, px

def write_png(path, w, h, rgb):
    raw = bytearray()
    for y in range(h): raw += b'\x00' + rgb[y*w*3:(y+1)*w*3]
    def chunk(t, b): return struct.pack('>I', len(b)) + t + b + struct.pack('>I', zlib.crc32(t + b) & 0xffffffff)
    open(path, 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(bytes(raw), 9)) + chunk(b'IEND', b''))

def main(src, dst, fill):
    W, H, px = read_png(src)
    # alpha bbox (alpha > 8)
    x0, y0, x1, y1 = W, H, -1, -1
    for y in range(H):
        row = px[y*W*4:(y+1)*W*4]
        for x in range(W):
            if row[4*x+3] > 8:
                if x < x0: x0 = x
                if x > x1: x1 = x
                if y < y0: y0 = y
                if y > y1: y1 = y
    bw, bh = x1 - x0 + 1, y1 - y0 + 1
    print(f'source {W}x{H}, mark bbox {bw}x{bh} at ({x0},{y0})')
    S = 1024; target = int(S * fill)
    scale = target / max(bw, bh)
    ow, oh = round(bw * scale), round(bh * scale)
    ox, oy = (S - ow) // 2, (S - oh) // 2
    print(f'mark rendered {ow}x{oh} at ({ox},{oy}); margins L/R {ox}/{S-ox-ow}, T/B {oy}/{S-oy-oh}')
    cream = (0xF5, 0xF0, 0xE8)
    out = bytearray(cream * (S * S))
    inv = 1 / scale
    for j in range(oh):
        sy0 = y0 + j * inv; sy1 = y0 + (j + 1) * inv
        ys = range(int(sy0), min(int(sy1) + 1, y1 + 1))
        for i in range(ow):
            sx0 = x0 + i * inv; sx1 = x0 + (i + 1) * inv
            xs = range(int(sx0), min(int(sx1) + 1, x1 + 1))
            r = g = b = a = 0; n = 0
            for yy in ys:
                base = yy * W * 4
                for xx in xs:
                    k = base + 4*xx; al = px[k+3]
                    r += px[k]*al; g += px[k+1]*al; b += px[k+2]*al; a += al; n += 1
            if a == 0: continue
            cov = a / (255 * n)   # coverage of this output pixel
            pr, pg, pb = r / a, g / a, b / a
            o = ((oy + j) * S + (ox + i)) * 3
            out[o]   = round(pr * cov + cream[0] * (1 - cov))
            out[o+1] = round(pg * cov + cream[1] * (1 - cov))
            out[o+2] = round(pb * cov + cream[2] * (1 - cov))
    write_png(dst, S, S, bytes(out))
    print('wrote', dst)

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2], float(sys.argv[3]))
