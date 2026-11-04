#ifndef EXTERIA_FMP4_H
#define EXTERIA_FMP4_H

#include "exteria_status.h"

/* a fragmented mp4 (a moov with empty sample tables and an mvex, then pairs of moof and mdat) written as the plain mp4 that every avfoundation back to ios 5 plays: the
   sample tables are built from the fragments, so the player has the length at once and can seek to any time. the samples are copied as they are, only the container
   changes. Telegram servers send videos in this form, and the player of an old phone shows a black picture, no length or a seek that starts over */

/* ok when the file is fragmented (it has a moof), not found when it is not, malformed for a damaged box list, io when it cannot be read. only the box headers are read, so
   it is cheap for a file of any size */
exteria_status exteria_fmp4_scan(const char *path);

/* writes the plain form of in_path to out_path. not found when the input is not fragmented (nothing is written), malformed for fragments that do not describe the file,
   unsupported for a layout the writer does not take, limit for a file that the 32 bit offsets of the plain form cannot address or that has more samples than the bound,
   io and nomem otherwise. a failed run leaves no output file. the input is read in pieces and never held whole */
exteria_status exteria_fmp4_remux(const char *in_path, const char *out_path);

#endif
