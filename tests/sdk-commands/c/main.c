/* The C SDK's protocol 1.1 commands in rhun (tests/ext-sdk-commands.py): the same program as
 * ../go/main.go, line for line in its log (standard error). */
#define RHUNEXT_IMPLEMENTATION
#include "rhunext.h"

static const char *code(rx_ext *ext, int r) {
    static char c[64];
    if (r >= 0) return "ok";
    snprintf(c, sizeof c, "%s", rx_error(ext));
    char *sp = strchr(c, ' ');
    if (sp) *sp = 0;
    return c;
}

static void on_ready(rx_ext *ext, const char *project, void *user) {
    (void)project, (void)user;
    rx_status_item it = {0};
    it.name = "go", it.align = "left", it.priority = 9, it.text = "$(play) Sample", it.tooltip = "Run the sample";
    it.command = "say", it.args = "from the status bar", it.args_len = 19;
    fprintf(stderr, "status %s\n", code(ext, rx_set_status_item(ext, &it)));
    fprintf(stderr, "context %s\n", code(ext, rx_set_context(ext, "mode", "ready")));
}

static void on_invoke(rx_ext *ext, const rx_invocation *inv, void *user) {
    (void)user;
    fprintf(stderr, "invoke %s doc=%lld from=%s", inv->name, (long long)inv->doc, inv->from);
    const char *t;
    const unsigned char *a;
    size_t tl, al;
    if (rx_menu_target(inv, &t, &tl, &a, &al) == 0) {
        /* the kind is the first word; a file, folder or root target's path the rest */
        const char *sp = memchr(t, ' ', tl);
        size_t kl = sp ? (size_t)(sp - t) : tl;
        int has_path = (kl == 4 && !memcmp(t, "file", 4)) || (kl == 6 && !memcmp(t, "folder", 6)) ||
                       (kl == 4 && !memcmp(t, "root", 4));
        fprintf(stderr, " target=%.*s path=%.*s args=%.*s", (int)kl, t, has_path && sp ? (int)(tl - kl - 1) : 0,
                sp ? sp + 1 : "", (int)al, (const char *)a);
    } else {
        fprintf(stderr, " body=%.*s", (int)inv->body_len, (const char *)inv->body);
    }
    fprintf(stderr, "\n");
    if (strcmp(inv->name, "jump") == 0) {
        fprintf(stderr, "goto_line %s\n", code(ext, rx_run_command(ext, "goto_line", "2", 1, NULL)));
    } else if (strcmp(inv->name, "ask_other") == 0) {
        rx_buf res = {NULL, 0, 0};
        int r = rx_run_command(ext, "bob/other.answer", "question", 8, &res);
        fprintf(stderr, "call result=%.*s %s\n", (int)res.len, res.data ? res.data : "", code(ext, r));
        rx_buf_free(&res);
    } else if (strcmp(inv->name, "mode") == 0) {
        char v[300];
        snprintf(v, sizeof v, "%.*s", (int)inv->body_len, (const char *)inv->body);
        fprintf(stderr, "mode %s %s\n", v, code(ext, rx_set_context(ext, "mode", v)));
    }
    fflush(stderr);
}

static int on_call(rx_ext *ext, const rx_call_ask *req, rx_buf *out, const char **c, void *user) {
    (void)ext, (void)c, (void)user;
    fprintf(stderr, "call %s from %s args=%.*s\n", req->name, req->caller, (int)req->args_len, (const char *)req->args);
    fflush(stderr);
    rx_buf_str(out, "answer to ");
    rx_buf_add(out, req->args, req->args_len);
    return 1;
}

int main(void) {
    rx_handlers h = {0};
    h.ready = on_ready;
    h.invoke = on_invoke;
    h.call = on_call;
    return rx_run("command-args context-keys status-items", &h, NULL);
}
