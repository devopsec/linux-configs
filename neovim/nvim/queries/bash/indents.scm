; Custom override of nvim-treesitter's bundled queries/bash/indents.scm.
; User config directories are searched before plugin directories on
; 'runtimepath', so this file replaces (not extends) the upstream one.
;
; The only change from upstream: (case_statement) is removed from the
; @indent.begin list below. Upstream indents everything between `case` and
; `esac` -- including the case labels themselves -- one level, and then
; (case_item) @indent.begin adds a further level for the body under each
; label, producing a double indent. Dropping (case_statement) here keeps
; case labels aligned with `case`/`esac`, while the body under each label
; (still driven by (case_item) @indent.begin) is indented exactly once.

[
  (if_statement)
  (for_statement)
  (while_statement)
  (function_definition)
  (compound_statement)
  (subshell)
  (command_substitution)
  (do_group)
  (case_item)
] @indent.begin

[
  "fi"
  "done"
  "esac"
  "}"
  ")"
  "then"
  "do"
  (elif_clause)
  (else_clause)
] @indent.branch

[
  "fi"
  "done"
  "esac"
  "}"
  ")"
] @indent.end
