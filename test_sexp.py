#
# Copyright (C) 2015 eNovance SAS <licensing@enovance.com>
#
# Author: Frederic Lepied <frederic.lepied@enovance.com>
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.

import unittest

import sexp


class TestSexp(unittest.TestCase):

    def test_tokenize(self):
        self.assertEqual(sexp.tokenize('(a b)'), ['(', 'a', 'b', ')'])

    def test_parse(self):
        self.assertEqual(sexp.parse_sexp('(a b)'), ['a', 'b'])

    def test_eval_empty(self):
        self.assertEqual(sexp.eval_sexp(sexp.parse_sexp('()')), [])

    def test_eval(self):
        self.assertEqual(sexp.eval_sexp(sexp.parse_sexp('(+  3 7)')),
                         10)

    def test_if(self):
        self.assertEqual(
            sexp.eval_sexp(
                sexp.parse_sexp('(if (= 1 1) 1 0)')),
            1)

    def test_quote(self):
        self.assertEqual(
            sexp.eval_sexp(
                sexp.parse_sexp('(quote (+ 1 1))')),
            ['+', 1, 1])

    def test_set(self):
        self.assertEqual(sexp.eval_sexp(sexp.parse_sexp('(setq a 10)')),
                         10)

    def test_env(self):
        d = {'a': 2}
        e = sexp.Env(d)
        e['b'] = 3
        self.assertEqual(e['a'], 2)
        self.assertEqual(e['b'], 3)

    def test_let(self):
        self.assertEqual(sexp.eval_sexp(sexp.parse_sexp('''
(let ((a 5))
  (setq a 7))
''')),
                         7)

    def test_nested_let(self):
        self.assertEqual(sexp.eval_sexp(sexp.parse_sexp('''
(let ((a 7))
  (let ()
    (setq a 5))
 a)
''')),
                         5)

    def test_lambda(self):
        self.assertEqual(sexp.eval_sexp(sexp.parse_sexp('''
(progn
  (setq f (lambda(x) (+ x 2)))
  (f 2))
''')),
                         4)

    def test_lambda2(self):
        self.assertEqual(sexp.eval_sexp(sexp.parse_sexp('''
(let
  ((f (lambda(x) (+ x 2))))
  (f 2))
''')),
                         4)

    def test_lambda3(self):
        self.assertEqual(sexp.eval_sexp(sexp.parse_sexp('''
((lambda(x) (+ x 2)) 2)
''')),
                         4)

if __name__ == "__main__":
    unittest.main()

# test_sexp.py ends here
