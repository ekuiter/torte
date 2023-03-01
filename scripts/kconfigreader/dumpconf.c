/*
 * Copyright (C) 2021 Christian Kaestner, Elias Kuiter
 * Inspired by prior version by Reinhart Tartler
 * Released under the terms of the GNU GPL v2.0.
 * This updated implementation is necessary to account for newer Kconfig constructs.
 */

#include <locale.h>
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/time.h>

#define LKC_DIRECT_LINK
#include "lkc.h"

char* getSymType(enum symbol_type t) {
	switch (t) {
#ifdef ENUM_S_UNKNOWN
		case S_UNKNOWN:
		fprintf(stderr, "Treating S_UNKNOWN symbol as integer\n");
		return "integer";
#endif
#ifdef ENUM_S_BOOLEAN
		case S_BOOLEAN: return "boolean";
#endif
#ifdef ENUM_S_TRISTATE
		case S_TRISTATE: return "tristate";
#endif
#ifdef ENUM_S_INT
		case S_INT: return "integer";
#endif
#ifdef ENUM_S_HEX
		case S_HEX: return "hex";
#endif
#ifdef ENUM_S_STRING
		case S_STRING: return "string";
#endif
#ifdef ENUM_S_OTHER
		case S_OTHER: return "other";
#endif
	}
	return "?";
}

char* getPropType(enum prop_type t) {
	switch (t) {
#ifdef ENUM_P_UNKNOWN
		case P_UNKNOWN: return "unknown";
#endif
#ifdef ENUM_P_PROMPT
   		case P_PROMPT: return "prompt";
#endif
#ifdef ENUM_P_COMMENT
        case P_COMMENT: return "comment";
#endif
#ifdef ENUM_P_MENU
        case P_MENU: return "menu";
#endif
#ifdef ENUM_P_DEFAULT
        case P_DEFAULT: return "default";
#endif
#ifdef ENUM_P_CHOICE
        case P_CHOICE: return "choice";
#endif
#ifdef ENUM_P_SELECT
        case P_SELECT: return "select";
#endif
#ifdef ENUM_P_RANGE
        case P_RANGE: return "range";
#endif
#ifdef ENUM_P_ENV
        case P_ENV: return "env";
#endif
#ifdef ENUM_P_SYMBOL
        case P_SYMBOL: return "symbol";
#endif
#ifdef ENUM_P_IMPLY
        case P_IMPLY: return "select";
#endif
	}
	return "?";
}

char* replace_char(char* str, char find, char replace){
	if (str == NULL)
		return NULL;
    char *current_pos = strchr(str,find);
    while (current_pos) {
        *current_pos = replace;
        current_pos = strchr(current_pos,find);
    }
    return str;
}

void dumpsymref(FILE *out, struct symbol *s) {
	replace_char(s->name, '&', '_'); // necessary to parse freetz-ng, which uses & characters in feature names
	if (s==&symbol_mod) 
		fprintf(out, "m");
	else if (s==&symbol_yes) 
		fprintf(out, "y");
	else if (s==&symbol_no) 
		fprintf(out, "n");
	else if ((s->flags & SYMBOL_CONST)) 
		fprintf(out, "'%s'", s->name);
	else if (s->type==S_UNKNOWN)
		fprintf(out, "'%s'", s->name);
#ifdef SYMBOL_AUTO
	else if (s->flags & SYMBOL_AUTO && !(s->flags & SYMBOL_CHOICE) && !(s->name)) //IGNORE
		fprintf(out, "IGNORE");
#endif
	else
		fprintf(out, "S@%d", s);
}

void dumpexpr(FILE *out, struct expr *e) {
	if (!e) {fprintf(out, "ERROR"); return;}
	enum expr_type t = e->type;
	switch (t) {
#ifdef ENUM_E_SYMBOL
	case E_SYMBOL:
		dumpsymref(out, e->left.sym);
		break;
#endif
#ifdef ENUM_E_NOT
	case E_NOT:
		fprintf(out, "!");
		dumpexpr(out, e->left.expr);
		break;
#endif
#ifdef ENUM_E_EQUAL
	case E_EQUAL:
		fprintf(out, "(");
		dumpsymref(out, e->left.sym);
		fprintf(out, "=");
		dumpsymref(out, e->right.sym);
		fprintf(out, ")");
		break;
#endif
#ifdef ENUM_E_UNEQUAL
	case E_UNEQUAL:
		fprintf(out, "(");
		dumpsymref(out, e->left.sym);
		fprintf(out, "!=");
		dumpsymref(out, e->right.sym);
		fprintf(out, ")");
		break;
#endif
#ifdef ENUM_E_OR
	case E_OR:
		fprintf(out, "(");
		dumpexpr(out, e->left.expr);
		fprintf(out, " || ");
		dumpexpr(out, e->right.expr);
		fprintf(out, ")");
		break;
#endif
#ifdef ENUM_E_AND
	case E_AND:
		fprintf(out, "(");
		dumpexpr(out, e->left.expr);
		fprintf(out, " &amp;&amp; ");
		dumpexpr(out, e->right.expr);
		fprintf(out, ")");
		break;
#endif
#ifdef ENUM_E_LIST
	case E_LIST:
		fprintf(out, "(");
		dumpsymref(out, e->right.sym);
		if (e->left.expr) {
			fprintf(out, " ^ ");
			dumpexpr(out, e->left.expr);
		}
		fprintf(out, ")");
		break;
#endif
#ifdef ENUM_E_RANGE
	case E_RANGE:
		fprintf(out, "[");
		dumpsymref(out, e->left.sym);
		fprintf(out, ",");
		dumpsymref(out, e->right.sym);
		fprintf(out, "]");
		break;
#endif
#ifdef ENUM_E_CHOICE
	case E_CHOICE:
		fprintf(out, "(");
		dumpsymref(out, e->right.sym);
		if (e->left.expr) {
			fprintf(out, " ^ ");
			dumpexpr(out, e->left.expr);
		}
		fprintf(out, ")");
		break;
#endif
#ifdef ENUM_E_NONE
	case E_NONE:
		fprintf(out, "y");
		fprintf(stderr, "Ignoring E_NONE expression\n");
		break;
#endif
#ifdef ENUM_E_LTH
	case E_LTH:
		fprintf(out, "y");
		fprintf(stderr, "Ignoring E_LTH expression\n");
		break;
#endif
#ifdef ENUM_E_LEQ
	case E_LEQ:
		fprintf(out, "y");
		fprintf(stderr, "Ignoring E_LEQ expression\n");
		break;
#endif
#ifdef ENUM_E_GTH
	case E_GTH:
		fprintf(out, "y");
		fprintf(stderr, "Ignoring E_GTH expression\n");
		break;
#endif
#ifdef ENUM_E_GEQ
	case E_GEQ:
		fprintf(out, "y");
		fprintf(stderr, "Ignoring E_GEQ expression\n");
		break;
#endif
	}
}


void dumpprop(FILE *out, struct property *prop) {
	fprintf(out, "<property type=\"%s\">",getPropType(prop->type));
	if (prop->text)	
    	fprintf(out, "<text><![CDATA[%s]]></text>", prop->text);
	if (prop->expr)	{
       	fprintf(out, "<expr>");
       	dumpexpr(out, prop->expr);
     	fprintf(out, "</expr>");
    }
	if (prop->visible.expr)	{
       	fprintf(out, "<visible><expr>");
       	dumpexpr(out, prop->visible.expr);
     	fprintf(out, "</expr></visible>");
    }

	fprintf(out, "</property>\n");
}


void dumpsymbol(FILE *out, struct symbol *sym) {
	struct property *prop;
	//while (sym) {
		fprintf(out, "<symbol type=\"%s\" flags=\"%d\" id=\"%d\">\n", getSymType(sym->type), sym->flags, sym);

		if (sym->name)	
       		fprintf(out, "<name>%s</name>\n", sym->name);

       	for (prop = sym->prop; prop; prop = prop->next) {
       		dumpprop(out, prop);
       	}

		fprintf(out, "</symbol>\n");
		//sym = sym->next;
	//}
}

void dumpmenu(FILE *out, struct menu *menu) {
//	struct property *prop;
	struct symbol *sym;

	fprintf(out, "<menu flags=\"%d\">\n", menu->flags);
	if ((sym = menu->sym))
			dumpsymbol(out, sym);
//	if ((prop = menu->prompt)) {
//			dumpprop(out, prop);
//	}
	if (menu->dep) {
		fprintf(out, "<dep>");
		dumpexpr(out, menu->dep);
		fprintf(out, "</dep>");
	}

	fprintf(out, "</menu>\n");
}

void myconfdump(FILE *out)
{
	struct menu *menu;

	menu = rootmenu.list;
	fprintf(out, "<submenu>\n");
	while (menu) {
		dumpmenu(out, menu);

		if (menu->list) {
			fprintf(out, "<submenu>\n");
			menu = menu->list;
		}
		else if (menu->next) {
			menu = menu->next;
		}
		else while ((menu = menu->parent)) {
			fprintf(out, "</submenu>\n");
			if (menu->next) {
				menu = menu->next;
				break;
			}
		}
	}
}

int main(int ac, char **av)
{
	struct stat tmpstat;
	char *arch = getenv("ARCH");

	setlocale(LC_ALL, "");

	if (stat(av[1], &tmpstat) != 0) {
		fprintf(stderr, "could not open %s\n", av[1]);
		exit(EXIT_FAILURE);
	}

	if (!arch) {
		fputs("setting arch ", stderr);
		arch = strdup ("x86");
	}
	fprintf(stderr, "using arch %s\n", arch);
	setenv("ARCH", arch, 1);
	setenv("KERNELVERSION", "2.6.30-vamos", 1);
	conf_parse(av[1]);
	fprintf(stdout, "\n.\n");
	myconfdump(stdout);
	return 0;
}
