#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <fcntl.h>

static void fatal (const char* msg)
{
	perror (msg);
	exit (-1);
}

static void* mmap_open (const char* fname)
{
	int fd = open (fname, O_RDONLY);
	if (fd == -1)
		fatal ("couldn't open file");

	struct stat st;
	if (fstat (fd, &st) == -1)
		fatal ("couldn't stat file");

	void* ptr = mmap (NULL, st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
	if (ptr == (void*)-1)
		fatal ("couldn't mmap file");

	return ptr;
}

typedef uint8_t db;
typedef uint16_t dw;
typedef uint32_t dd;
typedef uint64_t dq;

struct table {
	dd offset;
	dd length;
};

struct string {
	const char* ptr;
	size_t len;
};

struct header {
	dd signature;
	db version_major;
	db version_minor;
	dw header_length;
	dd input_file_string_offset;
	dd output_file_string_offset;
	struct table strings;
	struct table symbols;
	struct table preprocessed;
	struct table assembly;
	struct table section_names;
	struct table symbol_references;
};

struct assembly {
	dd output_file_offset;
	dd offset_preprocessed;
	dq virtual_address;
	dd extended_sib;
	dd relative_symbol;
	db address_type;
	db code_size; // 16, 32, 64
	db _notimplemented[2];
} __attribute__ ((packed));
_Static_assert(sizeof(struct assembly) == 28);

struct preprocessed {
	dd source_offset;
	dd line_number: 31;
	dd is_macro: 1;
	dd position;
	dd macro_offset;
	char tokenised[];
};
_Static_assert(sizeof(struct preprocessed) == 16);

static const void* listing_file;
static const void* output_file;

static bool fmt_preprocessed (char* buf, int len, const struct preprocessed* p)
{
	const char* tokens = p->tokenised;
	int tlen;

	for (;;) {
		char c = *tokens++;
		switch (c) {
		case 0x1a:
			tlen = *tokens++;
			if (tlen + 1 >= len)
				return false;
			*buf++ = ' ';
			memcpy (buf, tokens, tlen);
			buf += tlen;
			tokens += tlen;
			len -= tlen + 1;
			break;
		case 0x22:
			tlen = *(int*)tokens;
			tokens += 4;
			if (tlen + 2 >= len)
				return false;
			*buf++ = ' ';
			*buf++ = '"';
			memcpy (buf, tokens, tlen);
			buf += tlen;
			tokens += tlen;
			len -= tlen + 3;
			*buf++ = '"';
			break;
		case 0x3b: case 0:
			*buf = 0;
			return true;
		default:
			if (len <= 2)
				return false;
			if ((c != ',') && (c != ':')) {
				*buf++ = ' ';
				len--;
			}
			*buf++ = c;
			len--;
		}
	}
}

static void fmt_bytes (char* buf, int buflen, const db* src, int count)
{
	static const char* hex = "0123456789abcdef";

	memset (buf, ' ', buflen);
	buflen--;
	buf[buflen] = 0;

	while (count --> 0) {
		db b = *src++;
		if (buflen < 2)
			return;
		if (buflen == 2) {
			*buf++ = hex[b >> 4];
			*buf++ = hex[b & 15];
			return;
		}
		*buf++ = hex[b >> 4];
		*buf++ = hex[b & 15];
		*buf++ = ' ';
		buflen -= 3;
	}
}

static void print_assembly ()
{
	typedef const struct assembly* asm_t;

	const struct header* hd = listing_file;
	asm_t as = listing_file + hd->assembly.offset;
	dd len = hd->assembly.length / sizeof(struct assembly);

	for (dd i=0; i < len; i++) {
		asm_t a = &as[i];
		static char pbuf[80];
		static char obuf[24];
		const struct preprocessed* p =
			listing_file + hd->preprocessed.offset + a->offset_preprocessed;

		if (!fmt_preprocessed (pbuf, sizeof(pbuf), p))
			strcpy (pbuf, "<line too long>");

		int output_len;

		if (i+1 < len) {
			asm_t a_next = a + 1;
			output_len = a_next->output_file_offset - a->output_file_offset;
		} else {
			output_len = 0;
		}

		fmt_bytes (obuf, sizeof(obuf), output_file + a->output_file_offset, output_len);

		printf ("%8u %08zx | %s | %s\n", i, a->virtual_address, obuf, pbuf);
	}
}


int main (int argc, char** argv)
{
	if (argc < 2)
		fatal ("missing filename");

	listing_file = mmap_open (argv[1]);

	const struct header* hd = listing_file;
	const char* output_fname =
		listing_file + hd->strings.offset + hd->output_file_string_offset;

	output_file = mmap_open (output_fname);

	print_assembly ();
}
