# testing: what the test model puts in the editor: a glyph per test at its first line, failure
# marks at the places messages point to, and coverage tints.
.include "rhun.inc"

.text

# testgutter_item_gone(ext, index): an item went: its glyph and marks with it
FN testgutter_item_gone
    ret

# testgutter_item_changed(ext, index): an item's range or file changed
FN testgutter_item_changed
    ret
