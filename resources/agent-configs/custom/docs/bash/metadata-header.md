# Bash metadata comment header (spec)

Companion to `guidelines.md` (same folder); load only when adding or validating a package header.


## Section Usage

The metadata section is required for top-level package scripts, i.e. any entrypoint script in [packages](/packages).
For all other scripts this section is optional, and unless expicitly asked to add, should be omitted.  
If the metadata comment section is included, it must immediately follow the shebang or the shellcheck directive.

## Section Format

```bnf
<metadata-comment-section> ::= <section-open-line>
                                <package-tag-line>
                                <version-tag-line>
                                <summary-tag-line>
                                <optional-tag-line>*
                                <section-close-line>

<section-open-line>          ::= "#" "\n"
<section-close-line>         ::= "#" "\n"

<package-tag-line>           ::= "#" <pre-tag-ws> "PACKAGE:" <post-tag-ws> <package-value> "\n"
<version-tag-line>           ::= "#" <pre-tag-ws> "VERSION:" <post-tag-ws> <semver> "\n"
<summary-tag-line>           ::= "#" <pre-tag-ws> "SUMMARY:" <post-tag-ws> <text> "\n"

<optional-tag-line>          ::= <srcguard-tag-line>
                               | <varprefix-tag-line>
                               | <fnprefix-tag-line>
                               | <license-tag-line>

<srcguard-tag-line>          ::= "#" <pre-tag-ws> "SRCGUARD:" <post-tag-ws> <srcguard-value> "\n"
<varprefix-tag-line>         ::= "#" <pre-tag-ws> "VARPREFIX:" <post-tag-ws> <var-prefix-value> "\n"
<fnprefix-tag-line>          ::= "#" <pre-tag-ws> "FNPREFIX:" <post-tag-ws> <fn-prefix-value> "\n"
<license-tag-line>           ::= "#" <pre-tag-ws> "LICENSE:" <post-tag-ws> <text> "\n"

<pre-tag-ws>                 ::= " " | "\t"
<post-tag-ws>                ::= "  " | "\t\t"

<srcguard-value>             ::= "local" | "global" | "omitted"

<package-value>              ::= <lower-alphanum>+ ( "-" <lower-alphanum>+ )* 

<semver>                     ::= <digits> "." <digits> "." <digits> <rc-suffix>?
<rc-suffix>                  ::= "-rc" <digit> <digit>
<digits>                     ::= <digit>+

<var-prefix-value>           ::= <upper-alpha> ( <upper-alpha> | <digit> | "_" )*
<fn-prefix-value>            ::= <lower-alpha> ( <lower-alpha> | <digit> | "_" )*

<text>                       ::= <text-char>+
<text-char>                  ::= <alphanum> | " "
                               | "!" | "'" | "(" | ")" | '"' | "*" | "+" | "-" | "."
                               | "/" | "<" | "=" | ">" | "?" | "@" | "[" | "]" | "^"
                               | "_" | "{" | "|" | "}" | "~"

<alphanum>                   ::= <lower-alpha> | <upper-alpha> | <digit>
<lower-alphanum>             ::= <lower-alpha> | <digit>
<lower-alpha>                ::= "a" | "b" | "c" | "d" | "e" | "f" | "g" | "h" | "i" | "j"
                               | "k" | "l" | "m" | "n" | "o" | "p" | "q" | "r" | "s" | "t"
                               | "u" | "v" | "w" | "x" | "y" | "z"
<upper-alpha>                ::= "A" | "B" | "C" | "D" | "E" | "F" | "G" | "H" | "I" | "J"
                               | "K" | "L" | "M" | "N" | "O" | "P" | "Q" | "R" | "S" | "T"
                               | "U" | "V" | "W" | "X" | "Y" | "Z"
<digit>                      ::= "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9"
```

## Supported Metadata Tags

- PACKAGE
  - name of package defined by this script
  - globally unique within this project
  - required
- VERSION
  - semantic version of this package
  - required
- SUMMARY
  - description of what this package does or defines
  - required
- SRCGUARD
  - general scope of variable / function definitions
  - only valid for library packages
  - possible values:
    - local
      - definitions not available in child processes
    - global
      - definitions exported to child processes
    - omitted
      - purposefully omitted as design decision
      - subsequent imports or the library overwrite definitions
  - optional
  - default is local if not present
- VARPREFIX
  - prefix for variables defined in top-level session (session global)
  - only valid for library packages
  - full format of these variable names: `PREFIX + _ + NAME`
  - internal / private variable names use: `__ + PREFIX + _ + NAME`
  - optional
  - default is empty string if not present
- FNPREFIX
  - prefix for functions defined in top-level session (session global)
  - only valid for library packages
  - full format of these function names: `prefix + _ + name`
  - internal / private function names use: `__ + PREFIX + _ + NAME`
  - optional
  - default is empty string if not present
- LICENSE
  - license identifier for this package (may include other files)
  - optional
  - default is project license at root of this repo

## Executable Script Example

```bash
#
# PACKAGE:      core-logging-journald
# VERSION:      1.13.0
# SUMMARY:      Installs core system journald logging
#
```

## Library Script Example

```bash
#
# PACKAGE:      generator-tools-lib
# VERSION:      2.0.1
# SUMMARY:      Useful functions for generating data
#
```

