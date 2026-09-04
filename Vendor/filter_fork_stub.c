/*
 * Stubs for the two helpers libarchive's external-program filters call.
 *
 * This build compiles those filters without fork/vfork/posix_spawn -- no
 * sandboxed app may spawn a helper binary, and tvOS and watchOS mark the calls
 * unavailable outright. libarchive's own filter_fork_posix.c then compiles to
 * nothing, while archive_read_support_filter_program.c and
 * archive_write_add_filter_program.c still reference these two symbols
 * unconditionally, so the library would not link at all without them.
 *
 * Both callers already handle a failed spawn: they report "unable to run
 * program" and return ARCHIVE_FATAL. Failing here turns a link error into that
 * ordinary runtime error, and lzop, lrzip and grzip -- the formats that reach
 * for a helper -- report themselves as unsupported instead of vanishing from
 * archive_read_support_filter_all.
 */

#include <sys/types.h>

/* Matches libarchive/filter_fork.h, which refuses to be included outside the
 * library's own build. */
int __archive_create_child(const char *cmd, int *child_stdin, int *child_stdout,
                           pid_t *out_child);
void __archive_check_child(int in, int out);

int
__archive_create_child(const char *cmd, int *child_stdin, int *child_stdout,
                       pid_t *out_child)
{
	(void)cmd;
	(void)child_stdin;
	(void)child_stdout;
	(void)out_child;

	return (-30); /* ARCHIVE_FATAL */
}

void
__archive_check_child(int in, int out)
{
	(void)in;
	(void)out;
}
