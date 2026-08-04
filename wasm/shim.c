// Single entry point for the WebAssembly build behind docs/index.html.
//
// cmark-gfm's extension registration is several steps and easy to get wrong
// from JavaScript, so it stays here in C. The page renders the same input
// twice through this one function, differing only in the options bitmask, so
// a single .wasm serves both the strict and the tolerant column.

#include <stdlib.h>
#include <string.h>

#include "cmark-gfm.h"
#include "cmark-gfm-core-extensions.h"

static const char *EXTENSIONS[] = {"strikethrough", "table", "autolink",
                                   "tasklist"};

// fmt: 0 = HTML, 1 = XML (the AST view).
// The caller owns the returned buffer and must free() it.
char *tolerant_render(const char *md, int options, int fmt) {
  cmark_parser *parser;
  cmark_node *doc;
  char *out;
  size_t i;

  if (md == NULL)
    return NULL;

  cmark_gfm_core_extensions_ensure_registered();

  parser = cmark_parser_new(options);
  if (parser == NULL)
    return NULL;

  for (i = 0; i < sizeof(EXTENSIONS) / sizeof(EXTENSIONS[0]); i++) {
    cmark_syntax_extension *ext = cmark_find_syntax_extension(EXTENSIONS[i]);
    if (ext != NULL)
      cmark_parser_attach_syntax_extension(parser, ext);
  }

  cmark_parser_feed(parser, md, strlen(md));
  doc = cmark_parser_finish(parser);
  if (doc == NULL) {
    cmark_parser_free(parser);
    return NULL;
  }

  if (fmt == 1) {
    out = cmark_render_xml(doc, options);
  } else {
    out = cmark_render_html(doc, options,
                            cmark_parser_get_syntax_extensions(parser));
  }

  cmark_node_free(doc);
  cmark_parser_free(parser);
  return out;
}

// Exposed so the page can label itself without hardcoding a duplicate.
const char *tolerant_version(void) { return CMARK_GFM_VERSION_STRING; }
