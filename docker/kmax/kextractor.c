/*
 * Kmax
 * Copyright (C) 2012-2015 Paul Gazzillo, revised 2021-2024 Elias Kuiter
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

// This file is based on kmax/kextractors/kextractor-next-20210426/kextractor.c.

#include <locale.h>
#include <ctype.h>
#include <stdio.h>
#include <fcntl.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <getopt.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <stdbool.h>

#define LKC_DIRECT_LINK
#include "lkc.h"

// for_all_symbols was moved to internal.h in Linux 6.9:
// https://elixir.bootlin.com/linux/v6.9/C/ident/for_all_symbols
// https://github.com/torvalds/linux/commit/91b69454f93d1c905f3a56bb39856db9a220c791
#ifdef for_all_symbols
#define _for_all_symbols(sym) for_all_symbols(i, sym)
#else
#include "internal.h"
#define _for_all_symbols(sym) for_all_symbols(sym)
#endif

// sym_is_optional was removed in Linux 6.10:
// https://elixir.bootlin.com/linux/v6.9/C/ident/sym_is_optional
// https://github.com/torvalds/linux/commit/6a1215888e23aa9fbc514086402f04708c84f454
#ifndef SYM_IS_OPTIONAL
static inline bool sym_is_optional(struct symbol *sym)
{
	return false; // optional choices no longer exist since Linux 6.10
}
#endif

// sym_get_choice_prop was removed in Linux 6.11:
// https://elixir.bootlin.com/linux/v6.10/C/ident/sym_get_choice_prop
// https://github.com/torvalds/linux/commit/ca4c74ba306e28cebf53908e69b773dcbb700cbc
#ifdef SYM_GET_CHOICE_PROP
#define choice_type property
#define choice_function(sym) sym_get_choice_prop(sym)
#define choice_loop for (e = (choice->expr); e && (def_sym = e->right.sym); e = e->left.expr)
#else
#define choice_type menu
#define choice_function(sym) list_first_entry(&sym->menus, struct menu, link)
#define choice_loop list_for_each_entry(def_sym, &choice->choice_members, choice_link)
#endif

#define fopen(name, mode) ({                    \
      if (verbose)                              \
        printf("opening %s\n", name);           \
      fopen(name, mode);                        \
    })

#define truncate(str, len) ({                   \
      if (verbose)                              \
        printf("deleting %s\n", str);           \
      truncate(str, len);                       \
    })

static char *progname;
enum {
  A_NONE,
  A_CONFIGS,
  A_KCONFIGS,
  A_MENUSYMS,
  A_DEFAULTS,
  A_EXTRACT,
  A_DEPS,
  A_DUMP,
};
static int action = A_NONE;
static char* action_arg;
static bool verbose = false;
static char* forceoff = NULL;

struct linked_list {
  struct linked_list *next;
  void *data;
};

static struct linked_list *forceoffall = NULL;

static char *config_prefix = "CONFIG_";

static bool enable_reverse_dependencies = true;

bool is_symbol(struct symbol *);

static int _expr_compare_type(enum expr_type t1, enum expr_type t2)
{
	if (t1 == t2)
		return 0;
	switch (t1) {
#ifdef ENUM_E_LEQ
	case E_LEQ:
    if (t2 == E_EQUAL || t2 == E_UNEQUAL)
			return 1;
#endif
#ifdef ENUM_E_LTH
	case E_LTH:
    if (t2 == E_EQUAL || t2 == E_UNEQUAL)
			return 1;
#endif
#ifdef ENUM_E_GEQ
	case E_GEQ:
    if (t2 == E_EQUAL || t2 == E_UNEQUAL)
			return 1;
#endif
#ifdef ENUM_E_GTH
	case E_GTH:
		if (t2 == E_EQUAL || t2 == E_UNEQUAL)
			return 1;
#endif
#ifdef ENUM_E_EQUAL
	case E_EQUAL:
    if (t2 == E_NOT)
			return 1;
#endif
#if defined(ENUM_E_UNEQUAL) && defined(ENUM_E_NOT)
	case E_UNEQUAL:
		if (t2 == E_NOT)
			return 1;
#endif
#if defined(ENUM_E_NOT) && defined(ENUM_E_AND)
	case E_NOT:
		if (t2 == E_AND)
			return 1;
#endif
#if defined(ENUM_E_AND) && defined(ENUM_E_OR)
	case E_AND:
		if (t2 == E_OR)
			return 1;
#endif
#if defined(ENUM_E_OR) && defined(ENUM_E_LIST)
	case E_OR:
		if (t2 == E_LIST)
			return 1;
#endif
#ifdef ENUM_E_LIST // removed in Linux 6.11 (https://github.com/torvalds/linux/commit/7c9bb07a6e9439fb7bdeee15eb188fe127a0d0e0)
	case E_LIST:
		if (t2 == 0)
			return 1;
#endif
	default:
		return -1;
	}
	printf("[%dgt%d?]", t1, t2);
	return 0;
}

/*
 * See whether an expression contains the configuration variable name.
 * Recursively search in symbols referenced in the expression.
 */

void print_symbol_detail(FILE *out, struct symbol *sym, bool force_naked) {
  if (sym->name) {
    /* fprintf(stderr, "name = %s, type = %d\n", sym->name, sym->type); */
    if (strcmp(sym->name, "y") == 0 ||
        strcmp(sym->name, "m") == 0) {
      fprintf(out, "1");
    } else if (strcmp(sym->name, "n") == 0) {
      fprintf(out, "0");
    } else if (S_UNKNOWN == sym->type) {
      fprintf(out, "0");
    } else {
      if (! force_naked) {
        fprintf(out, "(defined CONFIG_%s)", sym->name);
      } else {
        fprintf(out, "CONFIG_%s", sym->name);
      }
    }
  } else {
    fprintf(out, "1");
  }
}

static void print_symbol(FILE *out, struct symbol *sym) {
  print_symbol_detail(out, sym, false);
}

// use E_NONE for first call to print_expr's prevtoken
 void my_print_expr(struct expr *e, FILE *out, enum expr_type prevtoken)
{
	if (_expr_compare_type(prevtoken, e->type) > 0)
		fprintf(out, "(");
	switch (e->type) {
#ifdef ENUM_E_NONE
  case E_NONE:
    break;
#endif
#ifdef ENUM_E_SYMBOL
  case E_SYMBOL:
    print_symbol(out, e->left.sym);
		break;
#endif
#ifdef ENUM_E_NOT
	case E_NOT:
    fprintf(out, "!");
    my_print_expr(e->left.expr, out, E_NOT);
		break;
#endif
#ifdef ENUM_E_EQUAL
	case E_EQUAL:
    if (strcmp(e->right.sym->name, "y") == 0 ||
        strcmp(e->right.sym->name, "m") == 0) {
      print_symbol(out, e->left.sym);
    } else if (strcmp(e->right.sym->name, "n") == 0) {
      fprintf(out, "!");
      print_symbol(out, e->left.sym);
    } else {
      // don't print (defined ... ) around config
      print_symbol_detail(out, e->left.sym, true);
      fprintf(out, "==");
      print_symbol_detail(out, e->right.sym, true);
    }
		break;
#endif
#ifdef ENUM_E_UNEQUAL
	case E_UNEQUAL:
    if (strcmp(e->right.sym->name, "y") == 0 ||
        strcmp(e->right.sym->name, "m") == 0) {
      fprintf(out, "!");
      print_symbol(out, e->left.sym);
    } else if (strcmp(e->right.sym->name, "n") == 0) {
      print_symbol(out, e->left.sym);
    } else {
      // don't print (defined ... ) around config
      print_symbol_detail(out, e->left.sym, true);
      fprintf(out, "!=");
      print_symbol_detail(out, e->right.sym, true);
    }
		break;
#endif
#ifdef ENUM_E_OR
	case E_OR:
    my_print_expr(e->left.expr, out, E_OR);
    fprintf(out, " || ");
    my_print_expr(e->right.expr, out, E_OR);
		break;
#endif
#ifdef ENUM_E_AND
	case E_AND:
    my_print_expr(e->left.expr, out, E_AND);
    fprintf(out, " && ");
    my_print_expr(e->right.expr, out, E_AND);
		break;
#endif
#ifdef ENUM_E_LIST
	case E_LIST:
    //E_LIST is created in menu_finalize and is related to <choice>
    print_symbol(out, e->right.sym);
    fprintf(out, " ");
		if (e->left.expr) {
      fprintf(out, "^ ");
      my_print_expr(e->left.expr, out, E_LIST);
		}
		break;
#endif
#ifdef ENUM_E_CHOICE
	case E_CHOICE:
    //E_LIST is created in menu_finalize and is related to <choice>
    print_symbol(out, e->right.sym);
    fprintf(out, " ");
		if (e->left.expr) {
      fprintf(out, "^ ");
      my_print_expr(e->left.expr, out, E_CHOICE);
		}
		break;
#endif
#ifdef ENUM_E_RANGE
	case E_RANGE:
    fprintf(out, "[");
    print_symbol(out, e->left.sym);
    print_symbol(out, e->right.sym);
    fprintf(out, "]");
		break;
#endif
	default:
		fprintf(out, "<unknown type %d>", e->type);
		break;
	}
	if (_expr_compare_type(prevtoken, e->type) > 0)
		fprintf(out, ")");
}

void print_python_symbol_detail(FILE *out, struct symbol *sym, bool force_naked) {
  if (sym->name) {
    if (strcmp(sym->name, "y") == 0 ||
        strcmp(sym->name, "m") == 0) {
      fprintf(out, "1");
    } else if (strcmp(sym->name, "n") == 0) {
      fprintf(out, "0");
    } else if (S_UNKNOWN == sym->type) {
      fprintf(out, "\"%s\"", sym->name);
    } else {
      if (! force_naked) {
        fprintf(out, "%s%s", config_prefix, sym->name);
      } else {
        fprintf(out, "%s%s", config_prefix, sym->name);
      }
    }
  } else {
    fprintf(out, "1");
  }
}

void print_python_symbol(FILE *out, struct symbol *sym) {
  print_python_symbol_detail(out, sym, false);
}

// use E_NONE for first call to print_expr's prevtoken
void print_python_expr(struct expr *e, FILE *out, enum expr_type prevtoken)
{
	if (_expr_compare_type(prevtoken, e->type) > 0)
		fprintf(out, "(");
	switch (e->type) {
#ifdef ENUM_E_NONE
  case E_NONE:
    break;
#endif
#ifdef ENUM_E_SYMBOL
	case E_SYMBOL:
    print_python_symbol(out, e->left.sym);
		break;
#endif
#ifdef ENUM_E_NOT
	case E_NOT:
    fprintf(out, " not ");
    print_python_expr(e->left.expr, out, E_NOT);
		break;
#endif
#ifdef ENUM_E_EQUAL
	case E_EQUAL:
    if (strcmp(e->right.sym->name, "y") == 0 ||
        strcmp(e->right.sym->name, "m") == 0) {
      print_python_symbol(out, e->left.sym);
    } else if (strcmp(e->right.sym->name, "n") == 0) {
      fprintf(out, " not ");
      print_python_symbol(out, e->left.sym);
    } else {
      // don't print (defined ... ) around config
      print_python_symbol_detail(out, e->left.sym, true);
      fprintf(out, "==");
      print_python_symbol_detail(out, e->right.sym, true);
    }
		break;
#endif
#ifdef ENUM_E_UNEQUAL
	case E_UNEQUAL:
    if (strcmp(e->right.sym->name, "y") == 0 ||
        strcmp(e->right.sym->name, "m") == 0) {
      fprintf(out, " not ");
      print_python_symbol(out, e->left.sym);
    } else if (strcmp(e->right.sym->name, "n") == 0) {
      print_python_symbol(out, e->left.sym);
    } else {
      // don't print (defined ... ) around config
      print_python_symbol_detail(out, e->left.sym, true);
      fprintf(out, "!=");
      print_python_symbol_detail(out, e->right.sym, true);
    }
		break;
#endif
#ifdef ENUM_E_OR
	case E_OR:
    print_python_expr(e->left.expr, out, E_OR);
    fprintf(out, " or ");
    print_python_expr(e->right.expr, out, E_OR);
		break;
#endif
#ifdef ENUM_E_AND
	case E_AND:
    print_python_expr(e->left.expr, out, E_AND);
    fprintf(out, " and ");
    print_python_expr(e->right.expr, out, E_AND);
		break;
#endif
#ifdef ENUM_E_LTH
	case E_LTH:
    print_python_symbol(out, e->left.sym);
    fprintf(out, " < ");
    print_python_symbol(out, e->right.sym);
		break;
#endif
#ifdef ENUM_E_LEQ
	case E_LEQ:
    print_python_symbol(out, e->left.sym);
    fprintf(out, " <= ");
    print_python_symbol(out, e->right.sym);
		break;
#endif
#ifdef ENUM_E_GTH
	case E_GTH:
    print_python_symbol(out, e->left.sym);
    fprintf(out, " > ");
    print_python_symbol(out, e->right.sym);
		break;
#endif
#ifdef ENUM_E_GEQ
	case E_GEQ:
    print_python_symbol(out, e->left.sym);
    fprintf(out, " >= ");
    print_python_symbol(out, e->right.sym);
		break;
#endif
#ifdef ENUM_E_LIST
	case E_LIST:
    //E_LIST is created in menu_finalize and is related to <choice>
    print_python_symbol(out, e->right.sym);
    fprintf(out, " ");
		if (e->left.expr) {
      fprintf(out, "^ ");
      my_print_expr(e->left.expr, out, E_LIST);
		}
		break;
#endif
#ifdef ENUM_E_CHOICE
	case E_CHOICE:
    //E_LIST is created in menu_finalize and is related to <choice>
    print_python_symbol(out, e->right.sym);
    fprintf(out, " ");
		if (e->left.expr) {
      fprintf(out, "^ ");
      my_print_expr(e->left.expr, out, E_CHOICE);
		}
		break;
#endif
#ifdef ENUM_E_RANGE
	case E_RANGE:
    fprintf(out, "[");
    print_python_symbol(out, e->left.sym);
    print_python_symbol(out, e->right.sym);
    fprintf(out, "]");
		break;
#endif
	/* default: */
	/*   { */
	/* 	fprintf(stderr, "fatal: unknown expression type", e->type); */
  /*   exit(1); */
	/* 	break; */
	/*   } */
	}
	if (_expr_compare_type(prevtoken, e->type) > 0)
		fprintf(out, ")");
}

static inline int expr_is_mod(struct expr *e)
{
	return !e || (e->type == E_SYMBOL && e->left.sym == &symbol_mod);
}

/*
 * See whether the symbol is a default.  Defaults are configuration
 * variables that are non-visible (i.e., have no user prompts), have
 * an always-true default, and do not have any reverse dependencies.
 */
bool is_default(struct symbol *sym)
{
  struct property *st;

  for_all_prompts(sym, st)
    return false;

  if (sym->rev_dep.expr && !expr_is_yes(sym->rev_dep.expr))
    return false;

  for_all_defaults(sym, st) {
    if (!st->visible.expr || expr_is_yes(st->visible.expr))
      if (expr_is_yes(st->expr) || expr_is_mod(st->expr))
        return true;
  }

  return false;
}

/* Always return false.  Used for the --everyno action. */
bool never(struct symbol *sym)
{
  return false;
}

/* Check whether a configuration variable should be forced to off */
bool check_forceoff(struct symbol *sym)
{
  struct linked_list *p;

  for (p = forceoffall; p != NULL; p = p->next)
    if (!strcmp(p->data, sym->name))
      return true;

  return NULL != forceoff && !strcmp(forceoff, sym->name);
}

/* Write out the config files with no configuration variables set */
void everyno(void)
{
  char *cfiles[] = { ".config",
                     "include/config/auto.conf.cmd",
                     "include/config/auto.conf",
                     "include/config/tristate.conf" };
  char *zfiles[] = { "include/generated/autoconf.h",
                     "include/config/auto.conf.cmd" };
  int i;

#define ARRAY_SIZE(a) (sizeof(a)/sizeof(*a))

  for (i = 0; i < ARRAY_SIZE(cfiles); i++)
    if (truncate(cfiles[i], 0))
      perror("truncate");

  for (i = 0; i < ARRAY_SIZE(zfiles); i++)
    if (truncate(zfiles[i], 0))
      perror("truncate");
}

bool is_symbol(struct symbol *sym)
{
#ifdef ENUM_P_SYMBOL // removed in Linux 6.11 (https://github.com/torvalds/linux/commit/96490176f1e11947be2bdd2700075275e2c27310)
  struct property *st;
  for_all_properties(sym, st, P_SYMBOL)
    return true;
#endif    
  return false;
}

void print_menusyms(struct menu *m)
{
  while (m) {
    if (m->sym && m->sym->name && strlen(m->sym->name) > 0)
      printf("%s\n", m->sym->name);
    if (m->list)
      print_menusyms(m->list);
    m = m->next;
  }
}

void print_usage(void)
{
  printf("USAGE\n");
  printf("%s [options] --ACTION Kconfig\n", progname);
  printf("\n");
  printf("OPTIONS\n");
  printf("-f, --forceoff var\tturn off var (only for --every* actions)\n");
  printf("-a, --forceoffall file\tturn off all vars in file\n");
  printf("-p, --no-prefix\t\tdon't add the CONFIG_ prefix to vars\n");
  printf("-P, --set-prefix PREFIX\tuse a custom prefix instead of the CONFIG_ prefix for var names\n");
  printf("-D, --direct-dependencies-only\tno reverse dependencies in extract output\n");
  printf("-o, --output\t\tfile to write extract to.  otherwise stdout.\n");
  printf("-v, --verbose\t\tverbose output\n");
  printf("-h, --help\t\tdisplay this help message\n");
  printf("\n");
  printf("ACTIONS\n");
  printf("--configs\tprint all config vars\n");
  printf("--kconfigs\tprint all config vars declared in kconfig files\n");
  printf("--menusyms\t"
         "print config vars declared in the Kconfig files (using menus)\n");
  printf("--defaults\tprint all configuration variables that are defaults\n");
  printf("--extract\t"
         "extract constraints in kclause format\n");
  printf("--deps VAR\tprint direct and reverse dependencies for VAR\n");
  printf("--dump\t\tdump configuration variables\n");
  printf("\n");
  exit(0);
}

int main(int argc, char **argv)
{
  int opt;
  char *kconfig;
  struct symbol *sym;
  int i;

  progname = argv[0];

  if (1 == argc)
    print_usage();

	setlocale(LC_ALL, "");
#define LOCALEDIR "/usr/share/locale"
	/* bindtextdomain(PACKAGE, LOCALEDIR); */
	/* textdomain(PACKAGE); */

  FILE *output_fp = stdout;
  bool output_file_arg = false;
  
  opterr = 0;
  while (1) {
    static struct option long_options[] = {
      {"configs", no_argument, &action, A_CONFIGS},
      {"kconfigs", no_argument, &action, A_KCONFIGS},
      {"menusyms", no_argument, &action, A_MENUSYMS},
      {"defaults", no_argument, &action, A_DEFAULTS},
      {"forceoff", required_argument, 0, 'f'},
      {"forceoffall", required_argument, 0, 'a'},
      {"extract", no_argument, &action, A_EXTRACT},
      {"deps", required_argument, &action ,A_DEPS},
      {"dump", no_argument, &action ,A_DUMP},
      {"Configure", no_argument, 0, 'C'},
      {"no-prefix", no_argument, 0, 'p'},
      {"set-prefix", required_argument, 0, 'P'},
      {"direct-dependencies-only", no_argument, 0, 'D'},
      {"output", required_argument, 0, 'o'},
      {"verbose", no_argument, 0, 'v'},
      {"help", no_argument, 0, 'h'},
      {0, 0, 0, 0}
    };

    int option_index = 0;

    opt = getopt_long(argc, argv, "pP:Dde:o:hf:a:v", long_options, &option_index);

    if (-1 == opt)
      break;

    FILE *tmp;
    char *line;
    size_t len;
    ssize_t read;
    struct linked_list *last;

    switch (opt) {
    case 0:
      action_arg = optarg;
      break;
    case 'f':
      forceoff = optarg;
      break;
    case 'a':
      tmp = fopen(optarg, "r");
      line = NULL;
      len = 0;

      if (!tmp) {
        perror("fopen");
        exit(1);
      }

      last = NULL;
      while ((read = getline(&line, &len, tmp)) != -1) {
        struct linked_list *tmp = malloc(sizeof(struct linked_list));
        char *p;

        for (p = line; *p != '\0'; p++)
          if (*p == '\n') {
            *p = '\0';
            break;
          }

        tmp->next = NULL;
        tmp->data = line;
        /* printf("%s\n", line); */
        if (NULL == last) {
          last = forceoffall = tmp;
        } else {
          last->next = tmp;
          last = tmp;
        }
        line = NULL;  //force getline to allocate a new buffer
      }
      fclose(tmp);
      break;
    case 'p':
      config_prefix = "";
      break;
    case 'P':
      config_prefix = optarg;
      break;
    case 'D':
      enable_reverse_dependencies = false;
      break;
    case 'o':
      if ((output_fp = fopen(optarg, "w")) == NULL) {
        fprintf(stderr, "can't open %s for writing\n", optarg);
        exit(1);
      }
      output_file_arg = true;
      break;
    case 'v':
      verbose = true;
      break;
    case 'h':
      print_usage();
      break;
    case ':':
    case '?':
      fprintf(stderr, "Invalid option or missing argument.  For help use -h\n");
      exit(1);
      break;
    }
  }

  if (A_NONE == action) {
    fprintf(stderr, "Please specify an action.  For help use -h.\n");
    exit(1);
  }

  if (optind < argc)
    kconfig = argv[optind++];
  else
    kconfig = "Kconfig";

  conf_parse(kconfig);

  switch (action) {
  case A_DEFAULTS:
  _for_all_symbols(sym) {
      static bool def;

      if (!sym->name || strlen(sym->name) == 0)
        continue;

      def = is_default(sym);
      if (def)
        printf("%s\n", sym->name);
    }
    break;
  case A_CONFIGS:
    _for_all_symbols(sym) {
      if (!sym->name || strlen(sym->name) == 0)
        continue;

      printf("%s\n", sym->name);
    }
    break;
  case A_KCONFIGS:
    _for_all_symbols(sym) {
      if (!sym->name || strlen(sym->name) == 0)
        continue;

      if (is_symbol(sym))
        printf("%s\n", sym->name);
    }
    break;
  case A_MENUSYMS:
    print_menusyms(rootmenu.list);
    break;
  case A_EXTRACT:
    _for_all_symbols(sym) {
      if (!sym->name || strlen(sym->name) == 0)
        continue;

      struct property *prop;
      char *typename;
      int is_string;
      int is_bool;

      switch (sym->type) {
      case S_BOOLEAN:
        // fall through
      case S_TRISTATE:

        switch (sym->type) {
        case S_BOOLEAN:
          is_bool = true;
          break;
        case S_TRISTATE:
          is_bool = false;
          break;
        default:
          is_bool = true;
          // should not reach here
          break;
        }

        typename = is_bool ? "bool" : "tristate";
        fprintf(output_fp, "config %s%s %s\n", config_prefix, sym->name, typename);
        // print prompt conditions, if any
        prop = NULL;
        for_all_prompts(sym, prop) {
          if ((NULL != prop)) {
            fprintf(output_fp, "prompt %s%s", config_prefix, sym->name);
            fprintf(output_fp, " (");
            if (NULL != prop->visible.expr) {
              print_python_expr(prop->visible.expr, output_fp, E_NONE);
            } else {
              fprintf(output_fp, "1");
            }
            fprintf(output_fp, ")");
            fprintf(output_fp, "\n");
          }
        }
        // print default values
        prop = NULL;
        for_all_defaults(sym, prop) {
          if ((NULL != prop) && (NULL != (prop->expr))) {
            fprintf(output_fp, "def_bool %s%s ", config_prefix, sym->name);
            print_python_expr(prop->expr, output_fp, E_NONE);
            fprintf(output_fp, "|(");
            if (NULL != prop->visible.expr) {
              print_python_expr(prop->visible.expr, output_fp, E_NONE);
            } else {
              fprintf(output_fp, "1");
            }
            fprintf(output_fp, ")");
            fprintf(output_fp, "\n");
          }
        }
        break;
      case S_INT:
        // fall through
      case S_HEX:
        // fall through
      case S_STRING:

        switch (sym->type) {
        case S_INT:
          is_string = false;
          break;
        case S_HEX:
          is_string = false;
          break;
        case S_STRING:
          is_string = true;
          break;
        default:
          is_string = true;
          // should not reach here
          break;
        }

        typename = is_string ? "string" : "number";
        
        fprintf(output_fp, "config %s%s %s\n", config_prefix, sym->name, typename);
        // print prompt conditions, if any
        prop = NULL;
        for_all_prompts(sym, prop) {
          if ((NULL != prop)) {
            fprintf(output_fp, "prompt %s%s", config_prefix, sym->name);
            fprintf(output_fp, " (");
            if (NULL != prop->visible.expr) {
              print_python_expr(prop->visible.expr, output_fp, E_NONE);
            } else {
              fprintf(output_fp, "1");
            }
            fprintf(output_fp, ")");
            fprintf(output_fp, "\n");
          }
        }
        // print default values
        prop = NULL;
        for_all_defaults(sym, prop) {
          if ((NULL != prop) && (NULL != (prop->expr))) {
            fprintf(output_fp, "def_nonbool %s%s ", config_prefix, sym->name);
            /* if (is_string) fprintf(output_fp, "\""); */
            print_python_expr(prop->expr, output_fp, E_NONE);
            /* if (is_string) fprintf(output_fp, "\""); */
            fprintf(output_fp, "|(");
            if (NULL != prop->visible.expr) {
              print_python_expr(prop->visible.expr, output_fp, E_NONE);
            } else {
              fprintf(output_fp, "1");
            }
            fprintf(output_fp, ")");
            fprintf(output_fp, "\n");
          }
        }
        break;
      case S_UNKNOWN:
        // fall through
      default:
        // can't deal with this
        break;
      }
    }

    // print all dependent config vars
    _for_all_symbols(sym) {
      if (sym_is_choice(sym)) {
        struct property *prop;
        struct choice_type *choice;
        struct symbol *def_sym;
        struct expr *e;

        choice = choice_function(sym);
	
	// print choice type, depending on config type and optional statement
	switch(sym->type) {
          case S_BOOLEAN:
            sym_is_optional(sym) ? fprintf(output_fp, "bool_opt_choice") : fprintf(output_fp, "bool_choice");
            break;
          case S_TRISTATE:
            sym_is_optional(sym) ? fprintf(output_fp, "tristate_opt_choice") : fprintf(output_fp, "tristate_choice");
            break;
          default:
            fprintf(stderr, "fatal: choice type can only be bool or tristate, otherwise is impossible due to the parser.\n");
            exit(1);
        }
        
        choice_loop {
          fprintf(output_fp, " %s%s", config_prefix, def_sym->name);  // any dependencies should be handled below with 'dep'
        }
        fprintf(output_fp, "|(");

	// Both depends on and visibility shoul be satisfied for 
	// the choice to be selectable.
	// Kconfig conjuncts depends on constraint to the 
	// visibility constraint, so that for choice, looking at
	// only the visibility is sufficient.
	// rev_dep of choice copies the visibility to prevent
	// non-optional choices have no selection (menu.c, l854) 
	// Thus, rev_dep is the same as visibiltiy except conjoing
	// 'm' which is currently not needed for kclause.
	// In sum, only visibility is needed as the condition of
	// choice.

        // for formatting
        int printed_expr = 0;
	prop = NULL;
        for_all_prompts(sym, prop) {
          if ((NULL != prop)) {

	    if (printed_expr) {
	      fprintf(stderr, "warning: encountered multiple prompts, ignoring.");
	      break;
	      // commented code below can handle the case where multiple
	      // prompts are defined, where satisfying any of them makes
	      // the config option visible. However, multiple prompts 
	      // raises a warning by Kconfig and we consider it as an 
	      // invalid use of Kconfig language. Thus, this code is 
              // commented for now. Note that, using this code here
              // means the code for prompt keyword should also reflect
              // this case.
	      //fprintf(output_fp, " or ");
	    }
	    
	    printed_expr = 1;
	    fprintf(output_fp, "(");
            if (NULL != prop->visible.expr) {
              print_python_expr(prop->visible.expr, output_fp, E_NONE);
            } else {
              fprintf(output_fp, "1");
            }
            fprintf(output_fp, ")");
          }
        }

        if (!printed_expr)
          fprintf(output_fp, "1");
        
        fprintf(output_fp, ")\n");
      }
      
      if (!sym->name || strlen(sym->name) == 0)
        continue;

      if (sym->type == S_TRISTATE ||
          sym->type == S_BOOLEAN ||
          sym->type == S_INT ||
          sym->type == S_HEX ||
          sym->type == S_STRING) {
        bool no_dependencies = true;
#ifdef ENUM_dir_dep
        if (sym->dir_dep.expr) {
          no_dependencies = false;
          fprintf(output_fp, "dep %s%s (", config_prefix, sym->name);
          print_python_expr(sym->dir_dep.expr, output_fp, E_NONE);
          fprintf(output_fp, ")\n");
        }
#endif

        if (enable_reverse_dependencies) {
          // print all the variables selected by this variable
          struct property *prop;
          for_all_properties(sym, prop, P_SELECT) {
            // the current var itself is the var doing the select
            // prop->expr is the variable being selected
            // prop->visible.expr is And(sym->dir_dept, select_dep) where select_dep
            // is the dependency for select defined as "select 'selected' if 'select_dep'"
            fprintf(output_fp, "select ");
            // note: this assumes that prop->expr is only a single
            // variable name, which zconf.y guarantees
            print_python_expr(prop->expr, output_fp, E_NONE);
            fprintf(output_fp, " %s%s (", config_prefix, sym->name);
            if (NULL != prop->visible.expr) {
              print_python_expr(prop->visible.expr, output_fp, E_NONE);
            } else {
              fprintf(output_fp, "1");
            }
            fprintf(output_fp, ")\n");
          }

          // print the reverse dependency for this variable
          if (sym->rev_dep.expr) {
            no_dependencies = false;
            fprintf(output_fp, "rev_dep %s%s (", config_prefix, sym->name);
            print_python_expr(sym->rev_dep.expr, output_fp, E_NONE);
            fprintf(output_fp, ")\n");
          }
        }

        // nonbools without dependencies should depend on true
        if (sym->type == S_INT ||
            sym->type == S_HEX ||
            sym->type == S_STRING) {
          if (no_dependencies) {
            fprintf(output_fp, "dep %s%s (1)\n", config_prefix, sym->name);
          }
        }
      } else {
        /* ffprintf(output_fp, stderr, "skipping %s\n", sym->name); */
      }
    }
    break;
  case A_DUMP:
    zconfdump(stdout);
    break;
  default:
    fprintf(stderr, "fatal error: unsupported action\n");
    exit(1);
    break;
  }

  if (output_file_arg) {
    fflush(output_fp);
    fclose(output_fp);
  }    

  return 0;
}
