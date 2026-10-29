#ifndef EXTERIA_ARTICLE_H
#define EXTERIA_ARTICLE_H

#include <stddef.h>
#include <stdint.h>
#include "exteria_status.h"

/* removes script elements from a bounded HTML document for the read-only article view */
exteria_status exteria_article_readonly(const uint8_t *html, size_t length, uint8_t *out, size_t capacity, size_t *written);

#endif
