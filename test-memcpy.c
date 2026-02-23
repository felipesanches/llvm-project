typedef unsigned int size_t;
void *memcpy(void *dst, const void *src, size_t n);

// Large memcpy — should use LDIR
void copy_large(char *dst, const char *src) {
    memcpy(dst, src, 100);
}

// Dynamic-size memcpy — should use LDIR
void copy_dynamic(char *dst, const char *src, size_t n) {
    memcpy(dst, src, n);
}

// Struct copy (compiler-generated memcpy)
struct Data {
    int a, b, c, d, e, f, g, h;
};

void copy_struct(struct Data *dst, const struct Data *src) {
    *dst = *src;
}
