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

''' Functions to implement a mini Lisp-like language
'''

from UserDict import UserDict


def tokenize(chars):
    "Convert a string of characters into a list of tokens."
    return chars.replace('(', ' ( ').replace(')', ' ) ').split()


def parse_sexp(program):
    "Read a lisp-like expression from a string."
    return listify(tokenize(program))


def listify(tokens):
    "Create lists from a sequence of tokens."
    if len(tokens) == 0:
        raise SyntaxError('unexpected EOF while reading')
    token = tokens.pop(0)
    if '(' == token:
        lst = []
        while tokens[0] != ')':
            lst.append(listify(tokens))
        # pop off ')'
        tokens.pop(0)
        return lst
    elif ')' == token:
        raise SyntaxError('unexpected )')
    else:
        return atomify(token)


def atomify(token):
    "Numbers become numbers; every other token is a symbol."
    try:
        return int(token)
    except ValueError:
        try:
            return float(token)
        except ValueError:
            if token[0] == "'" and token[-1] == "'":
                return token[1:-1]
            else:
                return token


def macro(func):
    'Decorator to define a function as a macro'
    func.macro = True
    return func


@macro
def if_(env, test, true, *false):
    '(if expr trueexpr [falseexpr1 falseexpr2...])'
    if eval_sexp(test, env):
        return eval_sexp(true, env)
    else:
        return eval_sexp(false, env)[-1]


@macro
def quote(_, exp):
    '(quote (+ 1 1))'
    return exp


@macro
def setq(env, name, val):
    '(setq name val)'
    ret = env[name] = eval_sexp(val, env)
    return ret


def progn(*exp):
    '(progn exp1 [exp2...])'
    return exp[-1]


class Env(UserDict):
    'Cascaded environment'

    def __init__(self, env, params=[], args=[]):
        UserDict.__init__(self)
        self.outer = env
        self.update(zip(params, args))

    def __getitem__(self, key):
        if key in self.data:
            return self.data[key]
        else:
            return self.outer.__getitem__(key)

    def __setitem__(self, key, val):
        if key in self.outer:
            self.outer[key] = val
        else:
            self.data[key] = val

    def __repr__(self):
        return repr(self.data) + '->' + repr(self.outer)


@macro
def let(env, vars_, *body):
    '(let vars body)'
    newenv = Env(env)
    for name, val in vars_:
        newenv[name] = eval_sexp(val, newenv)
    for exp in body[:-1]:
        eval_sexp(exp, newenv)
    return eval_sexp(body[-1], newenv)


class EndOfGame(Exception):
    pass


def exit_():
    raise EndOfGame


class Lambda(object):
    "(lambda(x) x)"

    macro = True

    def __init__(self, env, params, body):
        self.env, self.params, self.body = env, params, body

    def __call__(self, _, *args):
        newenv = Env(self.env, self.params, args)
        return eval_sexp(self.body, newenv)


def standard_env():
    "An environment with some standard procedures."
    env = dict()
    import math
    import operator as op
    env.update(vars(math))      # sin, cos, sqrt, pi, ...
    env.update({
        '+': op.add,
        '-': op.sub,
        '*': op.mul,
        '/': op.div,
        '>': op.gt,
        '<': op.lt,
        '>=': op.ge,
        '<=': op.le,
        '=': op.eq,
        'abs': abs,
        'append': op.add,
        'if': if_,
        'quote': quote,
        'progn': progn,
        'setq': setq,
        'let': let,
        'lambda': Lambda,
        'exit': exit_,
    })

    return env

_GLOBAL_ENV = standard_env()


def eval_sexp(exp, env=_GLOBAL_ENV):
    "Evaluate an expression in an environment."
    if isinstance(exp, str):      # variable reference or string
        try:
            return env[exp]
        except KeyError:
            return exp
    elif not isinstance(exp, list) or len(exp) == 0:  # constant literal
        return exp
    else:
        proc = eval_sexp(exp[0], env)
        if callable(proc):
            if 'macro' in dir(proc):
                return proc(env, *exp[1:])
            else:
                args = [eval_sexp(arg, env) for arg in exp[1:]]
                return proc(*args)
        else:
            args = [eval_sexp(arg, env) for arg in exp[1:]]
            return [proc] + args


def repl(prompt='sexp> '):
    "A prompt-read-eval-print loop."
    while True:
        try:
            val = eval_sexp(parse_sexp(raw_input(prompt)))
            if val is not None:
                print(sexpstr(val))
        except EndOfGame:
            break
        except Exception as expt:
            print(expt)


def sexpstr(exp):
    "Convert a Python object back into a Scheme-readable string."
    if isinstance(exp, list):
        return '(' + ' '.join(map(sexpstr, exp)) + ')'
    else:
        return str(exp)

# sexp.py ends here
