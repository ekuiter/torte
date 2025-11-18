# Copyright (C) 2025 Eric Ketzler, Elias Kuiter
# todo: we still have a small number of mistakes in the hierarchy. we could fix them by pushing the erroneous features into the flat hierarchy (to avoid wrong results). this would require an additional SAT check and considerable reworking of this script. also, the constraints are currently not simplified and just preserved as is. we could also create "near-correct" feature models that omit dead features, include all unconstrained features to improve the accuracy of extracted models, and have the correct feature hierarchy. however, whether this is desirable depends a bit on the use case.

import sys
from kconfiglib import Kconfig, Symbol, Choice, MENU, COMMENT, TYPE_TO_STR

def check_indent(string):
    indent = 0
    i = 0
    while(string[i] == ' '):
        indent+=1
        i+=1
    return indent


def indent_write(s, indent):
    global menu_lines
    menu_lines.append(indent*" " + s + "\n")

# using kconfiglib to extract the menu hierarchy from the Kconfig top node
def write_items(node, indent):
    while node:
        if isinstance(node.item, Symbol):
            indent_write("config " + node.item.name, indent)

        elif isinstance(node.item, Choice):
            indent_write("choice", indent)

        elif node.item == MENU:
            indent_write('menu "{}"'.format(node.prompt[0]), indent)

        elif node.item == COMMENT:
            indent_write('comment "{}"'.format(node.prompt[0]), indent)


        if node.list:
            write_items(node.list, indent + 2)

        node = node.next

# returns list of features and list of constraints from the input uvl file
def extract_uvl_features(uvl_lines):
    cindex = uvl_lines.index("constraints\n")
    constraints = uvl_lines[cindex : ]

    startindex = uvl_lines.index("\t\toptional\n") + 1
    uvl_features = uvl_lines[startindex : cindex]

    for i,feature in enumerate(uvl_features):
        uvl_features[i] = feature.strip() + "\n"

    return uvl_features, constraints

# extract a list of features from the extracted menu hierarchy
# note that this is not accurate because we also keep comments and choices since we need them later
def extract_menu_features(menu_lines):
    menu_features = []

    for line in menu_lines:
        feature = line.strip()

        if("config " in line and "comment" not in line):
            feature = feature.replace("config", "")
            feature = feature.strip()
            if(feature[0].isdigit()):
                feature = '"' + feature + '"'
            feature += "\n"
            menu_features.append(feature)

        elif("menu" in line):
            feature = feature.strip("menu").strip() + "\n"
            menu_features.append(feature)

        else:
            menu_features.append(feature)

    return menu_features

''' This uses the input uvl file and list of unconstrained features as a base to create a new uvl file, where the
    hierarchy implied by the Kconfig object is applied. Some features might appear in the Kconfig object that
    were not present in the input uvl. These features only appear as comments in the output. A second file will be
    output containing all the differing features. '''

def extract_hierarchy(menu_lines, uvl_features, menu_features, constraints):
    global uvl
    output = 'namespace root\n\nfeatures\n\tRoot\n'
    current_indent = 0
    tabstr = '\t\t\t'
    choice_nr = 0
    choice_tag = False
    check_usage = {}
    diff_kconfiglib = "Features in Kconfiglib but not in KClause:\n\n"
    diff_count = 0
    diff_kclause = "Features in KClause not in Kconfiglib: \n\n"

    for i,line in enumerate(menu_features):

        comment = ""
        menu_line = menu_lines[i]
        sym_type = ""

        if "config " in menu_line and "comment" not in menu_line:
             sym_type = TYPE_TO_STR[kconf.syms[line.strip().strip('"')].type]

        if line not in uvl_features:
            if ("config " in menu_line and "comment" not in menu_line):
                diff_kconfiglib += line
                diff_count += 1
                continue
        if line in uvl_features:
            del uvl_features[uvl_features.index(line)]

        if 'menu' in menu_line:
            if current_indent == check_indent(menu_line):
                if current_indent in check_usage:
                    if check_usage[current_indent] == "optional":
                        output += tabstr.removesuffix("\t") + "mandatory\n"
                        check_usage[current_indent] = "mandatory"
                else:
                    output += tabstr.removesuffix("\t") + "mandatory\n"
                    check_usage[current_indent] = "mandatory"
                output += tabstr + line.strip() + " {abstract}\n"

            elif current_indent < check_indent(menu_line):
                output += tabstr + "\tmandatory\n" + tabstr + '\t\t' + line.strip() + " {abstract}\n"
                tabstr += '\t\t'
                current_indent = check_indent(menu_line)
                check_usage[current_indent] = "mandatory"

            elif current_indent > check_indent(menu_line):
                choice_tag = False
                diff = current_indent - check_indent(menu_line)
                while diff > 0:
                    tabstr = tabstr.removesuffix('\t')
                    diff -= 1
                current_indent = check_indent(menu_line)
                if check_usage[current_indent] == "optional":
                    output += tabstr.removesuffix("\t") + "mandatory\n"
                    check_usage[current_indent] = "mandatory"
                output += tabstr + line.strip() + " {abstract}\n"

        elif 'config ' in menu_line and "comment " not in menu_line :
            if current_indent == check_indent(menu_line):
                if choice_tag == False:
                    if current_indent in check_usage:
                        if check_usage[current_indent] == "mandatory":
                            output += tabstr.removesuffix("\t") + "optional\n"
                            check_usage[current_indent] = "optional"
                    else:
                        output += tabstr.removesuffix("\t") + "optional\n"
                        check_usage[current_indent] = "optional"
                output += tabstr + comment

            elif current_indent < check_indent(menu_line):
                output += tabstr + "\toptional\n" + tabstr + '\t\t' + comment
                tabstr += '\t\t'
                current_indent = check_indent(menu_line)
                check_usage[current_indent] = "optional"

            elif current_indent > check_indent(menu_line):
                choice_tag = False
                diff = current_indent - check_indent(menu_line)
                while diff > 0:
                    tabstr = tabstr.removesuffix('\t')
                    diff -= 1
                current_indent = check_indent(menu_line)
                if check_usage[current_indent] == "mandatory":
                    output += tabstr.removesuffix("\t") + "optional\n"
                    check_usage[current_indent] = "optional"
                output += tabstr + comment

            if(sym_type == "hex" or sym_type == "int" or sym_type == "string"):
                output += line.strip() + " // " + sym_type + "\n"
            else:
                output += line

        elif 'choice' in menu_line:
            choice_tag = True
            if current_indent == check_indent(menu_line):
                if check_usage[current_indent] == "mandatory":
                    output += tabstr.removesuffix("\t") + "optional\n"
                    check_usage[current_indent] = "optional"
                output += tabstr + 'choice' + str(choice_nr) + ' {abstract}\n' + tabstr + '\tor\n'
                tabstr += '\t\t'

            elif current_indent < check_indent(menu_line):
                output += tabstr + "\toptional\n" + tabstr + '\t\t' + 'choice' + str(choice_nr) + ' {abstract}\n' + tabstr + '\t\t\tor\n'
                tabstr += '\t\t\t\t'
                current_indent = check_indent(menu_line)
                check_usage[current_indent] = "optional"

            elif current_indent > check_indent(menu_line):
                diff = current_indent - check_indent(menu_line)
                while diff > 0:
                    tabstr = tabstr.removesuffix('\t')
                    diff -= 1
                current_indent = check_indent(menu_line)
                if check_usage[current_indent] == "mandatory":
                    output += tabstr.removesuffix("\t") + "optional\n"
                    check_usage[current_indent] = "optional"
                output += tabstr + 'choice' + str(choice_nr) + ' {abstract}\n' + tabstr + '\tor\n'
                tabstr += '\t\t'

            choice_nr += 1
            current_indent += 2

        elif 'comment' in menu_line:
            pass

    diff_kconfiglib += "\nTotal Number: " + str(diff_count) + "\n\n\n"

    if check_usage[0] == "optional":
        output += "\t\tmandatory\n"
        check_usage[0] = "mandatory"
    output += '\t\t\t"Visibility-Features" {abstract}\n\t\t\t\toptional\n'

    nv_features = []
    for line in uvl_features:
        if "__VISIBILITY__" in line:
            output += 5*"\t" + line
        else:
            nv_features.append(line)
    del uvl_features

    if nv_features:
        output += "\t\toptional\n"
    for line in nv_features:
         output += "\t\t\t" + line
         diff_kclause += line

    diff_kclause += "\nTotal Number: " + str(len(nv_features))

    for line in constraints:
        output += line

    output_file = open(sys.argv[4], 'w')
    output_file.write(output)
    output_file.close()

    output_file = open(sys.argv[5], 'w')
    output_file.write(diff_kconfiglib + diff_kclause)
    output_file.close()

kconf = Kconfig(sys.argv[1])

uvl_file = open(sys.argv[2], "r")
uvl_lines = uvl_file.readlines()
uvl_file.close()

unconstrained_features_file = open(sys.argv[3], "r")
unconstrained_features = unconstrained_features_file.readlines()
unconstrained_features_file.close()

menu_lines = []
write_items(kconf.top_node, 0)
uvl_features, constraints = extract_uvl_features(uvl_lines)
uvl_features = uvl_features + unconstrained_features
menu_features = extract_menu_features(menu_lines)

extract_hierarchy(menu_lines, uvl_features, menu_features, constraints)