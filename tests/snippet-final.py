#!/usr/bin/env python3
"""Final snippet selections track their content through native edits and mirrors."""
import unittest
import snippets


class FinalSelections(snippets.Snippets):
    def test_final_only_selects_default_and_finishes(self):
        out=self.run_snippet(['print-state','type z','print-doc','cmd snippet_next','type q','print-doc'],
                             text='abc',fields=((0,1,2,0),))
        self.assertIn('col=3 sel=1 ',self.states(out)[0])
        self.assertIn('azc',out);self.assertIn('azqc',out)

    def test_tab_selects_final_after_edits_before_it(self):
        out=self.run_snippet(['type foo','key Tab','print-state','type z','print-doc'],
                             text='x result',fields=((1,0,1,0),(0,2,8,0)))
        self.assertIn('col=11 sel=6 ',self.states(out)[0]);self.assertIn('foo z',out)

    def test_preceding_occurrence_does_not_get_absorbed(self):
        out=self.run_snippet(['type z','key Tab','print-state','type q','print-doc'],
                             text='xxy',fields=((1,0,1,0),(1,1,2,0),(0,1,3,0)))
        self.assertIn('col=4 sel=2 ',self.states(out)[0]);self.assertIn('zq',out)

    def test_following_occurrence_does_not_get_absorbed(self):
        out=self.run_snippet(['type z','key Tab','print-state','type q','print-doc'],
                             text='yxx',fields=((1,2,3,0),(1,1,2,0),(0,0,2,0)))
        self.assertIn('col=3 sel=2 ',self.states(out)[0]);self.assertIn('qz',out)

    def test_earlier_mirror_moves_the_final_start_without_expanding_it(self):
        out=self.run_snippet(['type long','key Tab','print-state','print-doc','type q','print-doc'],
                             text='xxy',fields=((1,1,2,0),(1,0,1,0),(0,1,3,0)))
        self.assertIn('col=10 sel=5 ',self.states(out)[0]);self.assertIn('longlongy',out)
        self.assertIn('longq',out)

    def test_adjacent_substring_in_a_broad_field_stays_external(self):
        out=self.run_snippet(['key Home','key shift+Right','key shift+Right','type q',
                              'key Tab','print-state','print-doc','type z','print-doc'],
                             text='abXYcd',fields=((1,0,6,0),(0,2,4,1)))
        self.assertIn('col=4 sel=2 ',self.states(out)[0]);self.assertIn('qXYcd',out);self.assertIn('qzcd',out)

    def test_interior_collapse_then_later_retype_restores_final_range(self):
        out=self.run_snippet(['key Home','key Right','key shift+Right','key shift+Right',
                              'key BackSpace','type Z','key Tab','print-state','print-doc'],
                             text='aXYb',fields=((1,0,4,0),(0,1,3,1)))
        self.assertIn('col=3 sel=1 ',self.states(out)[0]);self.assertIn('aZb',out)

    def test_prefix_collapse_then_later_retype_restores_final_range(self):
        out=self.run_snippet(['key Home','key shift+Right','key shift+Right','key BackSpace',
                              'type Z','key Tab','print-state','print-doc'],
                             text='XYab',fields=((1,0,4,0),(0,0,2,1)))
        self.assertIn('col=2 sel=1 ',self.states(out)[0]);self.assertIn('Zab',out)

    def test_suffix_collapse_then_later_retype_restores_final_range(self):
        out=self.run_snippet(['key Right','key shift+Left','key shift+Left','key BackSpace',
                              'type Z','key Tab','print-state','print-doc'],
                             text='abXY',fields=((1,0,4,0),(0,2,4,1)))
        self.assertIn('col=4 sel=1 ',self.states(out)[0]);self.assertIn('abZ',out)

    def test_collapsed_range_does_not_capture_another_empty_field(self):
        out=self.run_snippet(['key Home','key shift+Right','key BackSpace','key Tab',
                              'type Z','key Tab','print-state','print-doc'],
                             text='xY',fields=((1,0,1,0),(2,1,1,0),(0,0,1,0)))
        self.assertIn('col=2 sel=0 ',self.states(out)[0]);self.assertIn('ZY',out)

    def test_choice_tab_undo_and_redo_restore_final_selection(self):
        out=self.run_snippet(['key Down','key Tab','print-state','print-doc','cmd undo',
                              'print-state','cmd redo','print-state','print-doc'],
                             text='x result x',fields=((1,0,1,0),(1,9,10,0),(0,2,8,0)),
                             choices=((1,('x','long')),))
        states=self.states(out)
        self.assertIn('col=12 sel=6 ',states[0]);self.assertIn('col=2 sel=1 ',states[1])
        self.assertIn('col=12 sel=6 ',states[2]);self.assertEqual(out.count('long result long'),2)

    def test_nested_final_selection_resumes_only_parent_links(self):
        out=self.run_snippet(['cmd demo.child','wait 100','type z','key Tab','print-state',
                              'type q','print-doc','key Tab','print-state'],
                             child_fields=((1,0,2,0),(1,3,5,0),(0,3,5,0)))
        self.assertIn('col=4 sel=1 ',self.states(out)[0]);self.assertIn('z q two z q',out)
        self.assertIn('col=8 sel=3 ',self.states(out)[1])

    def test_final_marker_can_cross_unrelated_fields_without_becoming_a_parent(self):
        out=self.run_snippet(['type X','key Tab','type Y','key Tab','print-state','type Z','print-doc'],
                             text='ab',fields=((0,0,2,0),(1,0,1,0),(2,1,2,0)))
        self.assertIn('col=3 sel=2 ',self.states(out)[0]);self.assertIn('Z',out)

for _name in dir(snippets.Snippets):
    if _name.startswith('test_'):
        setattr(FinalSelections,_name,None)

if __name__=='__main__':
    unittest.main()
