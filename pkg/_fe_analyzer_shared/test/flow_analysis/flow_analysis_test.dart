// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:_fe_analyzer_shared/src/flow_analysis/flow_analysis.dart';
import 'package:test/test.dart';

import 'flow_analysis_mini_ast.dart';

main() {
  group('API', () {
    test('asExpression_end promotes variables', () {
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        declare(x, initialized: true),
        x.read.as_('int').stmt,
        checkPromoted(x, 'int'),
      ]);
    });

    test('asExpression_end handles other expressions', () {
      var h = Harness();
      h.run([
        expr('Object').as_('int').stmt,
      ]);
    });

    test('assert_afterCondition promotes', () {
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        assert_(x.read.eq(nullLiteral),
            checkPromoted(x, 'int').thenExpr(expr('String'))),
      ]);
    });

    test('assert_end joins previous and ifTrue states', () {
      var h = Harness();
      var x = Var('x', 'int?');
      var y = Var('x', 'int?');
      var z = Var('x', 'int?');
      h.run([
        x.read.as_('int').stmt,
        z.read.as_('int').stmt,
        assert_(block([
          x.write(expr('int?')).stmt,
          z.write(expr('int?')).stmt,
        ]).thenExpr(x.read.notEq(nullLiteral).and(y.read.notEq(nullLiteral)))),
        // x should be promoted because it was promoted before the assert, and
        // it is re-promoted within the assert (if it passes)
        checkPromoted(x, 'int'),
        // y should not be promoted because it was not promoted before the
        // assert.
        checkNotPromoted(y),
        // z should not be promoted because it is demoted in the assert
        // condition.
        checkNotPromoted(z),
      ]);
    });

    test('conditional_thenBegin promotes true branch', () {
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        declare(x, initialized: true),
        x.read
            .notEq(nullLiteral)
            .conditional(checkPromoted(x, 'int').thenExpr(expr('int')),
                checkNotPromoted(x).thenExpr(expr('int')))
            .stmt,
        checkNotPromoted(x),
      ]);
    });

    test('conditional_elseBegin promotes false branch', () {
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        declare(x, initialized: true),
        x.read
            .eq(nullLiteral)
            .conditional(checkNotPromoted(x).thenExpr(expr('Null')),
                checkPromoted(x, 'int').thenExpr(expr('Null')))
            .stmt,
        checkNotPromoted(x),
      ]);
    });

    test('conditional_end keeps promotions common to true and false branches',
        () {
      var h = Harness();
      var x = Var('x', 'int?');
      var y = Var('y', 'int?');
      var z = Var('z', 'int?');
      h.run([
        declare(x, initialized: true),
        declare(y, initialized: true),
        declare(z, initialized: true),
        expr('bool')
            .conditional(
                block([
                  x.read.as_('int').stmt,
                  y.read.as_('int').stmt,
                ]).thenExpr(expr('Null')),
                block([
                  x.read.as_('int').stmt,
                  z.read.as_('int').stmt,
                ]).thenExpr(expr('Null')))
            .stmt,
        checkPromoted(x, 'int'),
        checkNotPromoted(y),
        checkNotPromoted(z),
      ]);
    });

    test('conditional joins true states', () {
      // if (... ? (x != null && y != null) : (x != null && z != null)) {
      //   promotes x, but not y or z
      // }
      var h = Harness();
      var x = Var('x', 'int?');
      var y = Var('y', 'int?');
      var z = Var('z', 'int?');
      h.run([
        declare(x, initialized: true),
        declare(y, initialized: true),
        declare(z, initialized: true),
        if_(
            expr('bool').conditional(
                x.read.notEq(nullLiteral).and(y.read.notEq(nullLiteral)),
                x.read.notEq(nullLiteral).and(z.read.notEq(nullLiteral))),
            [
              checkPromoted(x, 'int'),
              checkNotPromoted(y),
              checkNotPromoted(z),
            ]),
      ]);
    });

    test('conditional joins false states', () {
      // if (... ? (x == null || y == null) : (x == null || z == null)) {
      // } else {
      //   promotes x, but not y or z
      // }
      var h = Harness();
      var x = Var('x', 'int?');
      var y = Var('y', 'int?');
      var z = Var('z', 'int?');
      h.run([
        declare(x, initialized: true),
        declare(y, initialized: true),
        declare(z, initialized: true),
        if_(
            expr('bool').conditional(
                x.read.eq(nullLiteral).or(y.read.eq(nullLiteral)),
                x.read.eq(nullLiteral).or(z.read.eq(nullLiteral))),
            [],
            [
              checkPromoted(x, 'int'),
              checkNotPromoted(y),
              checkNotPromoted(z),
            ]),
      ]);
    });

    test('equalityOp(x != null) promotes true branch', () {
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        declare(x, initialized: true),
        if_(x.read.notEq(nullLiteral), [
          checkReachable(true),
          checkPromoted(x, 'int'),
        ], [
          checkReachable(true),
          checkNotPromoted(x),
        ]),
      ]);
    });

    test('equalityOp(x != null) when x is non-nullable', () {
      var h = Harness();
      var x = Var('x', 'int');
      h.run([
        declare(x, initialized: true),
        if_(x.read.notEq(nullLiteral), [
          checkReachable(true),
          checkNotPromoted(x),
        ], [
          checkReachable(true),
          checkNotPromoted(x),
        ])
      ]);
    });

    test('equalityOp(<expr> == <expr>) has no special effect', () {
      var h = Harness();
      h.run([
        if_(expr('int?').eq(expr('int?')), [
          checkReachable(true),
        ], [
          checkReachable(true),
        ]),
      ]);
    });

    test('equalityOp(<expr> != <expr>) has no special effect', () {
      var h = Harness();
      h.run([
        if_(expr('int?').notEq(expr('int?')), [
          checkReachable(true),
        ], [
          checkReachable(true),
        ]),
      ]);
    });

    test('equalityOp(x != <null expr>) does not promote', () {
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        declare(x, initialized: true),
        if_(x.read.notEq(expr('Null')), [
          checkNotPromoted(x),
        ], [
          checkNotPromoted(x),
        ]),
      ]);
    });

    test('equalityOp(x == null) promotes false branch', () {
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        declare(x, initialized: true),
        if_(x.read.eq(nullLiteral), [
          checkReachable(true),
          checkNotPromoted(x),
        ], [
          checkReachable(true),
          checkPromoted(x, 'int'),
        ]),
      ]);
    });

    test('equalityOp(x == null) when x is non-nullable', () {
      var h = Harness();
      var x = Var('x', 'int');
      h.run([
        declare(x, initialized: true),
        if_(x.read.eq(nullLiteral), [
          checkReachable(true),
          checkNotPromoted(x),
        ], [
          checkReachable(true),
          checkNotPromoted(x),
        ])
      ]);
    });

    test('equalityOp(null != x) promotes true branch', () {
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        declare(x, initialized: true),
        if_(nullLiteral.notEq(x.read), [
          checkPromoted(x, 'int'),
        ], [
          checkNotPromoted(x),
        ]),
      ]);
    });

    test('equalityOp(<null expr> != x) does not promote', () {
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        declare(x, initialized: true),
        if_(expr('Null').notEq(x.read), [
          checkNotPromoted(x),
        ], [
          checkNotPromoted(x),
        ]),
      ]);
    });

    test('equalityOp(null == x) promotes false branch', () {
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        declare(x, initialized: true),
        if_(nullLiteral.eq(x.read), [
          checkNotPromoted(x),
        ], [
          checkPromoted(x, 'int'),
        ]),
      ]);
    });

    test('equalityOp(null == null) equivalent to true', () {
      var h = Harness();
      h.run([
        if_(expr('Null').eq(expr('Null')), [
          checkReachable(true),
        ], [
          checkReachable(false),
        ]),
      ]);
    });

    test('equalityOp(null != null) equivalent to false', () {
      var h = Harness();
      h.run([
        if_(expr('Null').notEq(expr('Null')), [
          checkReachable(false),
        ], [
          checkReachable(true),
        ]),
      ]);
    });

    test('equalityOp(null == non-null) is not equivalent to false', () {
      var h = Harness();
      h.run([
        if_(expr('Null').eq(expr('int')), [
          checkReachable(true),
        ], [
          checkReachable(true),
        ]),
      ]);
    });

    test('equalityOp(null != non-null) is not equivalent to true', () {
      var h = Harness();
      h.run([
        if_(expr('Null').notEq(expr('int')), [
          checkReachable(true),
        ], [
          checkReachable(true),
        ]),
      ]);
    });

    test('equalityOp(non-null == null) is not equivalent to false', () {
      var h = Harness();
      h.run([
        if_(expr('int').eq(expr('Null')), [
          checkReachable(true),
        ], [
          checkReachable(true),
        ]),
      ]);
    });

    test('equalityOp(non-null != null) is not equivalent to true', () {
      var h = Harness();
      h.run([
        if_(expr('int').notEq(expr('Null')), [
          checkReachable(true),
        ], [
          checkReachable(true),
        ]),
      ]);
    });

    test('conditionEqNull() does not promote write-captured vars', () {
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        declare(x, initialized: true),
        if_(x.read.notEq(nullLiteral), [
          checkPromoted(x, 'int'),
        ]),
        localFunction([
          x.write(expr('int?')).stmt,
        ]),
        if_(x.read.notEq(nullLiteral), [
          checkNotPromoted(x),
        ]),
      ]);
    });

    test('doStatement_bodyBegin() un-promotes', () {
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        declare(x, initialized: true),
        x.read.as_('int').stmt,
        checkPromoted(x, 'int'),
        branchTarget((t) => do_([
              checkNotPromoted(x),
              x.write(expr('Null')).stmt,
            ], expr('bool'))),
      ]);
    });

    test('doStatement_bodyBegin() handles write captures in the loop', () {
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        declare(x, initialized: true),
        do_([
          x.read.as_('int').stmt,
          // The promotion should have no effect, because the second time
          // through the loop, x has been write-captured.
          checkNotPromoted(x),
          localFunction([
            x.write(expr('int?')).stmt,
          ]),
        ], expr('bool')),
      ]);
    });

    test('doStatement_conditionBegin() joins continue state', () {
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        declare(x, initialized: true),
        branchTarget((t) => do_(
                [
                  if_(x.read.notEq(nullLiteral), [
                    continue_(t),
                  ]),
                  return_(),
                  checkReachable(false),
                  checkNotPromoted(x),
                ],
                block([
                  checkReachable(true),
                  checkPromoted(x, 'int'),
                ]).thenExpr(expr('bool')))),
      ]);
    });

    test('doStatement_end() promotes', () {
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        declare(x, initialized: true),
        branchTarget((t) =>
            do_([], checkNotPromoted(x).thenExpr(x.read.eq(nullLiteral)))),
        checkPromoted(x, 'int'),
      ]);
    });

    test('finish checks proper nesting', () {
      var h = Harness();
      var e = expr('Null');
      var flow = FlowAnalysis<Node, Statement, Expression, Var, Type>(
          h, AssignedVariables<Node, Var>());
      flow.ifStatement_conditionBegin();
      flow.ifStatement_thenBegin(e);
      expect(() => flow.finish(), _asserts);
    });

    test('for_conditionBegin() un-promotes', () {
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        declare(x, initialized: true),
        x.read.as_('int').stmt,
        checkPromoted(x, 'int'),
        for_(null, checkNotPromoted(x).thenExpr(expr('bool')), null, [
          x.write(expr('int?')).stmt,
        ]),
      ]);
    });

    test('for_conditionBegin() handles write captures in the loop', () {
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        declare(x, initialized: true),
        x.read.as_('int').stmt,
        checkPromoted(x, 'int'),
        for_(
            null,
            block([
              x.read.as_('int').stmt,
              checkNotPromoted(x),
              localFunction([
                x.write(expr('int?')).stmt,
              ]),
            ]).thenExpr(expr('bool')),
            null,
            []),
      ]);
    });

    test('for_conditionBegin() handles not-yet-seen variables', () {
      var h = Harness();
      var x = Var('x', 'int?');
      var y = Var('y', 'int?');
      h.run([
        declare(y, initialized: true),
        y.read.as_('int').stmt,
        for_(null, declare(x, initialized: true).thenExpr(expr('bool')), null, [
          x.write(expr('Null')).stmt,
        ]),
      ]);
    });

    test('for_bodyBegin() handles empty condition', () {
      var h = Harness();
      h.run([
        for_(null, null, checkReachable(true).thenExpr(expr('Null')), []),
        checkReachable(false),
      ]);
    });

    test('for_bodyBegin() promotes', () {
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        for_(declare(x, initialized: true), x.read.notEq(nullLiteral), null, [
          checkPromoted(x, 'int'),
        ]),
      ]);
    });

    test('for_bodyBegin() can be used with a null statement', () {
      // This is needed for collection elements that are for-loops.
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        for_(declare(x, initialized: true), x.read.notEq(nullLiteral), null, [],
            forCollection: true),
      ]);
    });

    test('for_updaterBegin() joins current and continue states', () {
      // To test that the states are properly joined, we have three variables:
      // x, y, and z.  We promote x and y in the continue path, and x and z in
      // the current path.  Inside the updater, only x should be promoted.
      var h = Harness();
      var x = Var('x', 'int?');
      var y = Var('y', 'int?');
      var z = Var('z', 'int?');
      h.run([
        declare(x, initialized: true),
        declare(y, initialized: true),
        declare(z, initialized: true),
        branchTarget((t) => for_(
                null,
                expr('bool'),
                block([
                  checkPromoted(x, 'int'),
                  checkNotPromoted(y),
                  checkNotPromoted(z),
                ]).thenExpr(expr('Null')),
                [
                  if_(expr('bool'), [
                    x.read.as_('int').stmt,
                    y.read.as_('int').stmt,
                    continue_(t),
                  ]),
                  x.read.as_('int').stmt,
                  z.read.as_('int').stmt,
                ])),
      ]);
    });

    test('for_end() joins break and condition-false states', () {
      // To test that the states are properly joined, we have three variables:
      // x, y, and z.  We promote x and y in the break path, and x and z in the
      // condition-false path.  After the loop, only x should be promoted.
      var h = Harness();
      var x = Var('x', 'int?');
      var y = Var('y', 'int?');
      var z = Var('z', 'int?');
      h.run([
        declare(x, initialized: true),
        declare(y, initialized: true),
        declare(z, initialized: true),
        branchTarget((t) => for_(
                null, x.read.eq(nullLiteral).or(z.read.eq(nullLiteral)), null, [
              if_(expr('bool'), [
                x.read.as_('int').stmt,
                y.read.as_('int').stmt,
                break_(t),
              ]),
            ])),
        checkPromoted(x, 'int'),
        checkNotPromoted(y),
        checkNotPromoted(z),
      ]);
    });

    test('forEach_bodyBegin() un-promotes', () {
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        declare(x, initialized: true),
        x.read.as_('int').stmt,
        checkPromoted(x, 'int'),
        forEachWithNonVariable(expr('List<int?>'), [
          checkNotPromoted(x),
          x.write(expr('int?')).stmt,
        ]),
      ]);
    });

    test('forEach_bodyBegin() handles write captures in the loop', () {
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        declare(x, initialized: true),
        x.read.as_('int').stmt,
        checkPromoted(x, 'int'),
        forEachWithNonVariable(expr('List<int?>'), [
          x.read.as_('int').stmt,
          checkNotPromoted(x),
          localFunction([
            x.write(expr('int?')).stmt,
          ]),
        ]),
      ]);
    });

    test('forEach_bodyBegin() writes to loop variable', () {
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        declare(x, initialized: false),
        checkAssigned(x, false),
        forEachWithVariableSet(x, expr('List<int?>'), [
          checkAssigned(x, true),
        ]),
        checkAssigned(x, false),
      ]);
    });

    test('forEach_bodyBegin() pushes conservative join state', () {
      var h = Harness();
      var x = Var('x', 'int');
      h.run([
        declare(x, initialized: false),
        checkUnassigned(x, true),
        branchTarget((t) => forEachWithNonVariable(expr('List<int>'), [
              // Since a write to x occurs somewhere in the loop, x should no
              // longer be considered unassigned.
              checkUnassigned(x, false),
              break_(t), x.write(expr('int')).stmt,
            ])),
        // Even though the write to x is unreachable (since it occurs after a
        // break), x should still be considered "possibly assigned" because of
        // the conservative join done at the top of the loop.
        checkUnassigned(x, false),
      ]);
    });

    test('forEach_end() restores state before loop', () {
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        declare(x, initialized: true),
        forEachWithNonVariable(expr('List<int?>'), [
          x.read.as_('int').stmt,
          checkPromoted(x, 'int'),
        ]),
        checkNotPromoted(x),
      ]);
    });

    test('functionExpression_begin() cancels promotions of self-captured vars',
        () {
      var h = Harness();
      var x = Var('x', 'int?');
      var y = Var('y', 'int?');
      h.run([
        declare(x, initialized: true),
        declare(y, initialized: true),
        x.read.as_('int').stmt,
        y.read.as_('int').stmt,
        checkPromoted(x, 'int'),
        checkPromoted(y, 'int'),
        localFunction([
          // x is unpromoted within the local function
          checkNotPromoted(x), checkPromoted(y, 'int'),
          x.write(expr('int?')).stmt, x.read.as_('int').stmt,
        ]),
        // x is unpromoted after the local function too
        checkNotPromoted(x), checkPromoted(y, 'int'),
      ]);
    });

    test('functionExpression_begin() cancels promotions of other-captured vars',
        () {
      var h = Harness();
      var x = Var('x', 'int?');
      var y = Var('y', 'int?');
      h.run([
        declare(x, initialized: true), declare(y, initialized: true),
        x.read.as_('int').stmt, y.read.as_('int').stmt,
        checkPromoted(x, 'int'), checkPromoted(y, 'int'),
        localFunction([
          // x is unpromoted within the local function, because the write
          // might have been captured by the time the local function executes.
          checkNotPromoted(x), checkPromoted(y, 'int'),
          // And any effort to promote x fails, because there is no way of
          // knowing when the captured write might occur.
          x.read.as_('int').stmt,
          checkNotPromoted(x), checkPromoted(y, 'int'),
        ]),
        // x is still promoted after the local function, though, because the
        // write hasn't been captured yet.
        checkPromoted(x, 'int'), checkPromoted(y, 'int'),
        localFunction([
          // x is unpromoted inside this local function too.
          checkNotPromoted(x), checkPromoted(y, 'int'),
          x.write(expr('int?')).stmt,
        ]),
        // And since the second local function captured x, it remains
        // unpromoted.
        checkNotPromoted(x), checkPromoted(y, 'int'),
      ]);
    });

    test('functionExpression_begin() cancels promotions of written vars', () {
      var h = Harness();
      var x = Var('x', 'int?');
      var y = Var('y', 'int?');
      h.run([
        declare(x, initialized: true), declare(y, initialized: true),
        x.read.as_('int').stmt, y.read.as_('int').stmt,
        checkPromoted(x, 'int'), checkPromoted(y, 'int'),
        localFunction([
          // x is unpromoted within the local function, because the write
          // might have happened by the time the local function executes.
          checkNotPromoted(x), checkPromoted(y, 'int'),
          // But it can be re-promoted because the write isn't captured.
          x.read.as_('int').stmt,
          checkPromoted(x, 'int'), checkPromoted(y, 'int'),
        ]),
        // x is still promoted after the local function, though, because the
        // write hasn't occurred yet.
        checkPromoted(x, 'int'), checkPromoted(y, 'int'),
        x.write(expr('int?')).stmt,
        // x is unpromoted now.
        checkNotPromoted(x), checkPromoted(y, 'int'),
      ]);
    });

    test('functionExpression_begin() handles not-yet-seen variables', () {
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        localFunction([]),
        // x is declared after the local function, so the local function
        // cannot possibly write to x.
        declare(x, initialized: true), x.read.as_('int').stmt,
        checkPromoted(x, 'int'), x.write(expr('Null')).stmt,
      ]);
    });

    test('functionExpression_begin() handles not-yet-seen write-captured vars',
        () {
      var h = Harness();
      var x = Var('x', 'int?');
      var y = Var('y', 'int?');
      h.run([
        declare(y, initialized: true),
        y.read.as_('int').stmt,
        localFunction([
          x.read.as_('int').stmt,
          // Promotion should not occur, because x might be write-captured by
          // the time this code is reached.
          checkNotPromoted(x),
        ]),
        localFunction([
          declare(x, initialized: true),
          x.write(expr('Null')).stmt,
        ]),
      ]);
    });

    test(
        'functionExpression_end does not propagate "definitely unassigned" '
        'data', () {
      var h = Harness();
      var x = Var('x', 'int');
      h.run([
        declare(x, initialized: false),
        checkUnassigned(x, true),
        localFunction([
          // The function expression could be called at any time, so x might
          // be assigned now.
          checkUnassigned(x, false),
        ]),
        // But now that we are back outside the function expression, we once
        // again know that x is unassigned.
        checkUnassigned(x, true),
        x.write(expr('int')).stmt,
        checkUnassigned(x, false),
      ]);
    });

    test('handleBreak handles deep nesting', () {
      var h = Harness();
      h.run([
        branchTarget((t) => while_(booleanLiteral(true), [
              if_(expr('bool'), [
                if_(expr('bool'), [
                  break_(t),
                ]),
              ]),
              return_(),
              checkReachable(false),
            ])),
        checkReachable(true),
      ]);
    });

    test('handleBreak handles mixed nesting', () {
      var h = Harness();
      h.run([
        branchTarget((t) => while_(booleanLiteral(true), [
              if_(expr('bool'), [
                if_(expr('bool'), [
                  break_(t),
                ]),
                break_(t),
              ]),
              break_(t),
              checkReachable(false),
            ])),
        checkReachable(true),
      ]);
    });

    test('handleContinue handles deep nesting', () {
      var h = Harness();
      h.run([
        branchTarget((t) => do_([
              if_(expr('bool'), [
                if_(expr('bool'), [
                  continue_(t),
                ]),
              ]),
              return_(),
              checkReachable(false),
            ], checkReachable(true).thenExpr(booleanLiteral(true)))),
        checkReachable(false),
      ]);
    });

    test('handleContinue handles mixed nesting', () {
      var h = Harness();
      h.run([
        branchTarget((t) => do_([
              if_(expr('bool'), [
                if_(expr('bool'), [
                  continue_(t),
                ]),
                continue_(t),
              ]),
              continue_(t),
              checkReachable(false),
            ], checkReachable(true).thenExpr(booleanLiteral(true)))),
        checkReachable(false),
      ]);
    });

    test('ifNullExpression allows ensure guarding', () {
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        declare(x, initialized: true),
        x.read
            .ifNull(block([
              checkReachable(true),
              x.write(expr('int')).stmt,
              checkPromoted(x, 'int'),
            ]).thenExpr(expr('int?')))
            .thenStmt(block([
              checkReachable(true),
              checkPromoted(x, 'int'),
            ]))
            .stmt,
      ]);
    });

    test('ifNullExpression allows promotion of tested var', () {
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        declare(x, initialized: true),
        x.read
            .ifNull(block([
              checkReachable(true),
              x.read.as_('int').stmt,
              checkPromoted(x, 'int'),
            ]).thenExpr(expr('int?')))
            .thenStmt(block([
              checkReachable(true),
              checkPromoted(x, 'int'),
            ]))
            .stmt,
      ]);
    });

    test('ifNullExpression discards promotions unrelated to tested expr', () {
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        declare(x, initialized: true),
        expr('int?')
            .ifNull(block([
              checkReachable(true),
              x.read.as_('int').stmt,
              checkPromoted(x, 'int'),
            ]).thenExpr(expr('int?')))
            .thenStmt(block([
              checkReachable(true),
              checkNotPromoted(x),
            ]))
            .stmt,
      ]);
    });

    test('ifNullExpression does not detect when RHS is unreachable', () {
      var h = Harness();
      h.run([
        expr('int')
            .ifNull(checkReachable(true).thenExpr(expr('int')))
            .thenStmt(checkReachable(true))
            .stmt,
      ]);
    });

    test('ifNullExpression determines reachability correctly for `Null` type',
        () {
      var h = Harness();
      h.run([
        expr('Null')
            .ifNull(checkReachable(true).thenExpr(expr('Null')))
            .thenStmt(checkReachable(true))
            .stmt,
      ]);
    });

    test('ifStatement with early exit promotes in unreachable code', () {
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        declare(x, initialized: true),
        return_(),
        checkReachable(false),
        if_(x.read.eq(nullLiteral), [
          return_(),
        ]),
        checkReachable(false),
        checkPromoted(x, 'int'),
      ]);
    });

    test('ifStatement_end(false) keeps else branch if then branch exits', () {
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        declare(x, initialized: true),
        if_(x.read.eq(nullLiteral), [
          return_(),
        ]),
        checkPromoted(x, 'int'),
      ]);
    });

    void _checkIs(String declaredType, String tryPromoteType,
        String expectedPromotedTypeThen, String expectedPromotedTypeElse,
        {bool inverted = false}) {
      var h = Harness();
      var x = Var('x', declaredType);
      h.run([
        declare(x, initialized: true),
        if_(x.read.is_(tryPromoteType, isInverted: inverted), [
          checkReachable(true),
          checkPromoted(x, expectedPromotedTypeThen),
        ], [
          checkReachable(true),
          checkPromoted(x, expectedPromotedTypeElse),
        ])
      ]);
    }

    test('isExpression_end promotes to a subtype', () {
      _checkIs('int?', 'int', 'int', 'Never?');
    });

    test('isExpression_end promotes to a subtype, inverted', () {
      _checkIs('int?', 'int', 'Never?', 'int', inverted: true);
    });

    test('isExpression_end does not promote to a supertype', () {
      _checkIs('int', 'int?', null, null);
    });

    test('isExpression_end does not promote to a supertype, inverted', () {
      _checkIs('int', 'int?', null, null, inverted: true);
    });

    test('isExpression_end does not promote to an unrelated type', () {
      _checkIs('int', 'String', null, null);
    });

    test('isExpression_end does not promote to an unrelated type, inverted',
        () {
      _checkIs('int', 'String', null, null, inverted: true);
    });

    test('isExpression_end does nothing if applied to a non-variable', () {
      var h = Harness();
      h.run([
        if_(expr('Null').is_('int'), [
          checkReachable(true),
        ], [
          checkReachable(true),
        ]),
      ]);
    });

    test('isExpression_end does nothing if applied to a non-variable, inverted',
        () {
      var h = Harness();
      h.run([
        if_(expr('Null').isNot('int'), [
          checkReachable(true),
        ], [
          checkReachable(true),
        ]),
      ]);
    });

    test('isExpression_end() does not promote write-captured vars', () {
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        declare(x, initialized: true),
        if_(x.read.is_('int'), [
          checkPromoted(x, 'int'),
        ]),
        localFunction([
          x.write(expr('int?')).stmt,
        ]),
        if_(x.read.is_('int'), [
          checkNotPromoted(x),
        ]),
      ]);
    });

    test('isExpression_end() handles not-yet-seen variables', () {
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        if_(x.read.is_('int'), [
          checkPromoted(x, 'int'),
        ]),
        declare(x, initialized: true),
        localFunction([
          x.write(expr('Null')).stmt,
        ]),
      ]);
    });

    test('labeledBlock without break', () {
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        declare(x, initialized: true),
        if_(x.read.isNot('int'), [
          labeled(return_()),
        ]),
        checkPromoted(x, 'int'),
      ]);
    });

    test('labeledBlock with break joins', () {
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        declare(x, initialized: true),
        if_(x.read.isNot('int'), [
          branchTarget((t) => labeled(block([
                if_(expr('bool'), [
                  break_(t),
                ]),
                return_(),
              ]))),
        ]),
        checkNotPromoted(x),
      ]);
    });

    test('logicalBinaryOp_rightBegin(isAnd: true) promotes in RHS', () {
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        declare(x, initialized: true),
        x.read
            .notEq(nullLiteral)
            .and(checkPromoted(x, 'int').thenExpr(expr('bool')))
            .stmt,
      ]);
    });

    test('logicalBinaryOp_rightEnd(isAnd: true) keeps promotions from RHS', () {
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        declare(x, initialized: true),
        if_(expr('bool').and(x.read.notEq(nullLiteral)), [
          checkPromoted(x, 'int'),
        ]),
      ]);
    });

    test('logicalBinaryOp_rightEnd(isAnd: false) keeps promotions from RHS',
        () {
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        declare(x, initialized: true),
        if_(expr('bool').or(x.read.eq(nullLiteral)), [], [
          checkPromoted(x, 'int'),
        ]),
      ]);
    });

    test('logicalBinaryOp_rightBegin(isAnd: false) promotes in RHS', () {
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        declare(x, initialized: true),
        x.read
            .eq(nullLiteral)
            .or(checkPromoted(x, 'int').thenExpr(expr('bool')))
            .stmt,
      ]);
    });

    test('logicalBinaryOp(isAnd: true) joins promotions', () {
      // if (x != null && y != null) {
      //   promotes x and y
      // }
      var h = Harness();
      var x = Var('x', 'int?');
      var y = Var('y', 'int?');
      h.run([
        declare(x, initialized: true),
        declare(y, initialized: true),
        if_(x.read.notEq(nullLiteral).and(y.read.notEq(nullLiteral)), [
          checkPromoted(x, 'int'),
          checkPromoted(y, 'int'),
        ]),
      ]);
    });

    test('logicalBinaryOp(isAnd: false) joins promotions', () {
      // if (x == null || y == null) {} else {
      //   promotes x and y
      // }
      var h = Harness();
      var x = Var('x', 'int?');
      var y = Var('y', 'int?');
      h.run([
        declare(x, initialized: true),
        declare(y, initialized: true),
        if_(x.read.eq(nullLiteral).or(y.read.eq(nullLiteral)), [], [
          checkPromoted(x, 'int'),
          checkPromoted(y, 'int'),
        ]),
      ]);
    });

    test('nonNullAssert_end(x) promotes', () {
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        declare(x, initialized: true),
        x.read.nonNullAssert.stmt,
        checkPromoted(x, 'int'),
      ]);
    });

    test('nullAwareAccess temporarily promotes', () {
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        declare(x, initialized: true),
        x.read
            .nullAwareAccess(block([
              checkReachable(true),
              checkPromoted(x, 'int'),
            ]).thenExpr(expr('Null')))
            .stmt,
        checkNotPromoted(x),
      ]);
    });

    test('nullAwareAccess does not promote the target of a cascade', () {
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        declare(x, initialized: true),
        x.read
            .nullAwareAccess(
                block([
                  checkReachable(true),
                  checkNotPromoted(x),
                ]).thenExpr(expr('Null')),
                isCascaded: true)
            .stmt,
      ]);
    });

    test('nullAwareAccess preserves demotions', () {
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        declare(x, initialized: true),
        x.read.as_('int').stmt,
        expr('int')
            .nullAwareAccess(block([
              checkReachable(true),
              checkPromoted(x, 'int'),
            ]).thenExpr(x.write(expr('int?'))).thenStmt(checkNotPromoted(x)))
            .stmt,
        checkNotPromoted(x),
      ]);
    });

    test('nullAwareAccess_end ignores shorting if target is non-nullable', () {
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        declare(x, initialized: true),
        expr('int')
            .nullAwareAccess(block([
              checkReachable(true),
              x.read.as_('int').stmt,
              checkPromoted(x, 'int'),
            ]).thenExpr(expr('Null')))
            .stmt,
        // Since the null-shorting path was reachable, promotion of `x` should
        // be cancelled.
        checkNotPromoted(x),
      ]);
    });

    test('parenthesizedExpression preserves promotion behaviors', () {
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        if_(
            x.read.parenthesized.notEq(nullLiteral.parenthesized).parenthesized,
            [
              checkPromoted(x, 'int'),
            ]),
      ]);
    });

    test('promote promotes to a subtype and sets type of interest', () {
      var h = Harness();
      var x = Var('x', 'num?');
      h.run([
        declare(x, initialized: true),
        checkNotPromoted(x),
        x.read.as_('num').stmt,
        checkPromoted(x, 'num'),
        // Check that it's a type of interest by promoting and de-promoting.
        if_(x.read.is_('int'), [
          checkPromoted(x, 'int'),
          x.write(expr('num')).stmt,
          checkPromoted(x, 'num'),
        ]),
      ]);
    });

    test('promote does not promote to a non-subtype', () {
      var h = Harness();
      var x = Var('x', 'num?');
      h.run([
        declare(x, initialized: true),
        checkNotPromoted(x),
        x.read.as_('String').stmt,
        checkNotPromoted(x),
      ]);
    });

    test('promote does not promote if variable is write-captured', () {
      var h = Harness();
      var x = Var('x', 'num?');
      h.run([
        declare(x, initialized: true),
        checkNotPromoted(x),
        localFunction([
          x.write(expr('num')).stmt,
        ]),
        x.read.as_('num').stmt,
        checkNotPromoted(x),
      ]);
    });

    test('promotedType handles not-yet-seen variables', () {
      // Note: this is needed for error recovery in the analyzer.
      var h = Harness();
      var x = Var('x', 'int');
      h.run([
        checkNotPromoted(x),
        declare(x, initialized: true),
      ]);
    });

    test('switchStatement_beginCase(false) restores previous promotions', () {
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        declare(x, initialized: true),
        x.read.as_('int').stmt,
        switch_(
            expr('Null'),
            [
              case_([
                checkPromoted(x, 'int'),
                x.write(expr('int?')).stmt,
                checkNotPromoted(x),
              ]),
              case_([
                checkPromoted(x, 'int'),
                x.write(expr('int?')).stmt,
                checkNotPromoted(x),
              ]),
            ],
            isExhaustive: false),
      ]);
    });

    test('switchStatement_beginCase(false) does not un-promote', () {
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        declare(x, initialized: true),
        x.read.as_('int').stmt,
        switch_(
            expr('Null'),
            [
              case_([
                checkPromoted(x, 'int'),
                x.write(expr('int?')).stmt,
                checkNotPromoted(x),
              ])
            ],
            isExhaustive: false),
      ]);
    });

    test('switchStatement_beginCase(false) handles write captures in cases',
        () {
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        declare(x, initialized: true),
        x.read.as_('int').stmt,
        switch_(
            expr('Null'),
            [
              case_([
                checkPromoted(x, 'int'),
                localFunction([
                  x.write(expr('int?')).stmt,
                ]),
                checkNotPromoted(x),
              ]),
            ],
            isExhaustive: false),
      ]);
    });

    test('switchStatement_beginCase(true) un-promotes', () {
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        declare(x, initialized: true),
        x.read.as_('int').stmt,
        switch_(
            expr('Null'),
            [
              case_([
                checkNotPromoted(x),
                x.write(expr('int?')).stmt,
                checkNotPromoted(x),
              ], hasLabel: true),
            ],
            isExhaustive: false),
      ]);
    });

    test('switchStatement_beginCase(true) handles write captures in cases', () {
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        declare(x, initialized: true),
        x.read.as_('int').stmt,
        switch_(
            expr('Null'),
            [
              case_([
                x.read.as_('int').stmt,
                checkNotPromoted(x),
                localFunction([
                  x.write(expr('int?')).stmt,
                ]),
                checkNotPromoted(x),
              ], hasLabel: true),
            ],
            isExhaustive: false),
      ]);
    });

    test('switchStatement_end(false) joins break and default', () {
      var h = Harness();
      var x = Var('x', 'int?');
      var y = Var('y', 'int?');
      var z = Var('z', 'int?');
      h.run([
        declare(x, initialized: true),
        declare(y, initialized: true),
        declare(z, initialized: true),
        y.read.as_('int').stmt,
        z.read.as_('int').stmt,
        branchTarget((t) => switch_(
            expr('Null'),
            [
              case_([
                x.read.as_('int').stmt,
                y.write(expr('int?')).stmt,
                break_(t),
              ]),
            ],
            isExhaustive: false)),
        checkNotPromoted(x),
        checkNotPromoted(y),
        checkPromoted(z, 'int'),
      ]);
    });

    test('switchStatement_end(true) joins breaks', () {
      var h = Harness();
      var w = Var('w', 'int?');
      var x = Var('x', 'int?');
      var y = Var('y', 'int?');
      var z = Var('z', 'int?');
      h.run([
        declare(w, initialized: true),
        declare(x, initialized: true),
        declare(y, initialized: true),
        declare(z, initialized: true),
        x.read.as_('int').stmt,
        y.read.as_('int').stmt,
        z.read.as_('int').stmt,
        branchTarget((t) => switch_(
            expr('Null'),
            [
              case_([
                w.read.as_('int').stmt,
                y.read.as_('int').stmt,
                x.write(expr('int?')).stmt,
                break_(t),
              ]),
              case_([
                w.read.as_('int').stmt,
                x.read.as_('int').stmt,
                y.write(expr('int?')).stmt,
                break_(t),
              ]),
            ],
            isExhaustive: true)),
        checkPromoted(w, 'int'),
        checkNotPromoted(x),
        checkNotPromoted(y),
        checkPromoted(z, 'int'),
      ]);
    });

    test('switchStatement_end(true) allows fall-through of last case', () {
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        declare(x, initialized: true),
        branchTarget((t) => switch_(
            expr('Null'),
            [
              case_([
                x.read.as_('int').stmt,
                break_(t),
              ]),
              case_([]),
            ],
            isExhaustive: true)),
        checkNotPromoted(x),
      ]);
    });

    test('tryCatchStatement_bodyEnd() restores pre-try state', () {
      var h = Harness();
      var x = Var('x', 'int?');
      var y = Var('y', 'int?');
      h.run([
        declare(x, initialized: true),
        declare(y, initialized: true),
        y.read.as_('int').stmt,
        tryCatch([
          x.read.as_('int').stmt,
          checkPromoted(x, 'int'),
          checkPromoted(y, 'int'),
        ], [
          catch_(body: [
            checkNotPromoted(x),
            checkPromoted(y, 'int'),
          ])
        ]),
      ]);
    });

    test('tryCatchStatement_bodyEnd() un-promotes variables assigned in body',
        () {
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        declare(x, initialized: true),
        x.read.as_('int').stmt,
        checkPromoted(x, 'int'),
        tryCatch([
          x.write(expr('int?')).stmt,
          x.read.as_('int').stmt,
          checkPromoted(x, 'int'),
        ], [
          catch_(body: [
            checkNotPromoted(x),
          ]),
        ]),
      ]);
    });

    test('tryCatchStatement_bodyEnd() preserves write captures in body', () {
      // Note: it's not necessary for the write capture to survive to the end of
      // the try body, because an exception could occur at any time.  We check
      // this by putting an exit in the try body.
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        declare(x, initialized: true),
        x.read.as_('int').stmt,
        checkPromoted(x, 'int'),
        tryCatch([
          localFunction([
            x.write(expr('int?')).stmt,
          ]),
          return_(),
        ], [
          catch_(body: [
            x.read.as_('int').stmt,
            checkNotPromoted(x),
          ])
        ]),
      ]);
    });

    test('tryCatchStatement_catchBegin() restores previous post-body state',
        () {
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        declare(x, initialized: true),
        tryCatch([], [
          catch_(body: [
            x.read.as_('int').stmt,
            checkPromoted(x, 'int'),
          ]),
          catch_(body: [
            checkNotPromoted(x),
          ]),
        ]),
      ]);
    });

    test('tryCatchStatement_catchBegin() initializes vars', () {
      var h = Harness();
      var e = Var('e', 'int');
      var st = Var('st', 'StackTrace');
      h.run([
        tryCatch([], [
          catch_(exception: e, stackTrace: st, body: [
            checkAssigned(e, true),
            checkAssigned(st, true),
          ]),
        ]),
      ]);
    });

    test('tryCatchStatement_catchEnd() joins catch state with after-try state',
        () {
      var h = Harness();
      var x = Var('x', 'int?');
      var y = Var('y', 'int?');
      var z = Var('z', 'int?');
      h.run([
        declare(x, initialized: true), declare(y, initialized: true),
        declare(z, initialized: true),
        tryCatch([
          x.read.as_('int').stmt,
          y.read.as_('int').stmt,
        ], [
          catch_(body: [
            x.read.as_('int').stmt,
            z.read.as_('int').stmt,
          ]),
        ]),
        // Only x should be promoted, because it's the only variable
        // promoted in both the try body and the catch handler.
        checkPromoted(x, 'int'), checkNotPromoted(y), checkNotPromoted(z),
      ]);
    });

    test('tryCatchStatement_catchEnd() joins catch states', () {
      var h = Harness();
      var x = Var('x', 'int?');
      var y = Var('y', 'int?');
      var z = Var('z', 'int?');
      h.run([
        declare(x, initialized: true), declare(y, initialized: true),
        declare(z, initialized: true),
        tryCatch([
          return_(),
        ], [
          catch_(body: [
            x.read.as_('int').stmt,
            y.read.as_('int').stmt,
          ]),
          catch_(body: [
            x.read.as_('int').stmt,
            z.read.as_('int').stmt,
          ]),
        ]),
        // Only x should be promoted, because it's the only variable promoted
        // in both catch handlers.
        checkPromoted(x, 'int'), checkNotPromoted(y), checkNotPromoted(z),
      ]);
    });

    test('tryFinallyStatement_finallyBegin() restores pre-try state', () {
      var h = Harness();
      var x = Var('x', 'int?');
      var y = Var('y', 'int?');
      h.run([
        declare(x, initialized: true),
        declare(y, initialized: true),
        y.read.as_('int').stmt,
        tryFinally([
          x.read.as_('int').stmt,
          checkPromoted(x, 'int'),
          checkPromoted(y, 'int'),
        ], [
          checkNotPromoted(x),
          checkPromoted(y, 'int'),
        ]),
      ]);
    });

    test(
        'tryFinallyStatement_finallyBegin() un-promotes variables assigned in '
        'body', () {
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        declare(x, initialized: true),
        x.read.as_('int').stmt,
        checkPromoted(x, 'int'),
        tryFinally([
          x.write(expr('int?')).stmt,
          x.read.as_('int').stmt,
          checkPromoted(x, 'int'),
        ], [
          checkNotPromoted(x),
        ]),
      ]);
    });

    test('tryFinallyStatement_finallyBegin() preserves write captures in body',
        () {
      // Note: it's not necessary for the write capture to survive to the end of
      // the try body, because an exception could occur at any time.  We check
      // this by putting an exit in the try body.
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        declare(x, initialized: true),
        tryFinally([
          localFunction([
            x.write(expr('int?')).stmt,
          ]),
          return_(),
        ], [
          x.read.as_('int').stmt,
          checkNotPromoted(x),
        ]),
      ]);
    });

    test('tryFinallyStatement_end() restores promotions from try body', () {
      var h = Harness();
      var x = Var('x', 'int?');
      var y = Var('y', 'int?');
      h.run([
        declare(x, initialized: true), declare(y, initialized: true),
        tryFinally([
          x.read.as_('int').stmt,
          checkPromoted(x, 'int'),
        ], [
          checkNotPromoted(x),
          y.read.as_('int').stmt,
          checkPromoted(y, 'int'),
        ]),
        // Both x and y should now be promoted.
        checkPromoted(x, 'int'), checkPromoted(y, 'int'),
      ]);
    });

    test(
        'tryFinallyStatement_end() does not restore try body promotions for '
        'variables assigned in finally', () {
      var h = Harness();
      var x = Var('x', 'int?');
      var y = Var('y', 'int?');
      h.run([
        declare(x, initialized: true), declare(y, initialized: true),
        tryFinally([
          x.read.as_('int').stmt,
          checkPromoted(x, 'int'),
        ], [
          checkNotPromoted(x),
          x.write(expr('int?')).stmt,
          y.write(expr('int?')).stmt,
          y.read.as_('int').stmt,
          checkPromoted(y, 'int'),
        ]),
        // x should not be re-promoted, because it might have been assigned a
        // non-promoted value in the "finally" block.  But y's promotion still
        // stands, because y was promoted in the finally block.
        checkNotPromoted(x), checkPromoted(y, 'int'),
      ]);
    });

    test('whileStatement_conditionBegin() un-promotes', () {
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        declare(x, initialized: true),
        x.read.as_('int').stmt,
        checkPromoted(x, 'int'),
        while_(checkNotPromoted(x).thenExpr(expr('bool')), [
          x.write(expr('Null')).stmt,
        ]),
      ]);
    });

    test('whileStatement_conditionBegin() handles write captures in the loop',
        () {
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        declare(x, initialized: true),
        x.read.as_('int').stmt,
        checkPromoted(x, 'int'),
        while_(
            block([
              x.read.as_('int').stmt,
              checkNotPromoted(x),
              localFunction([
                x.write(expr('int?')).stmt,
              ]),
            ]).thenExpr(expr('bool')),
            []),
      ]);
    });

    test('whileStatement_conditionBegin() handles not-yet-seen variables', () {
      var h = Harness();
      var x = Var('x', 'int?');
      var y = Var('y', 'int?');
      h.run([
        declare(y, initialized: true),
        y.read.as_('int').stmt,
        while_(declare(x, initialized: true).thenExpr(expr('bool')), [
          x.write(expr('Null')).stmt,
        ]),
      ]);
    });

    test('whileStatement_bodyBegin() promotes', () {
      var h = Harness();
      var x = Var('x', 'int?');
      h.run([
        declare(x, initialized: true),
        while_(x.read.notEq(nullLiteral), [
          checkPromoted(x, 'int'),
        ]),
      ]);
    });

    test('whileStatement_end() joins break and condition-false states', () {
      // To test that the states are properly joined, we have three variables:
      // x, y, and z.  We promote x and y in the break path, and x and z in the
      // condition-false path.  After the loop, only x should be promoted.
      var h = Harness();
      var x = Var('x', 'int?');
      var y = Var('y', 'int?');
      var z = Var('z', 'int?');
      h.run([
        declare(x, initialized: true),
        declare(y, initialized: true),
        declare(z, initialized: true),
        branchTarget(
            (t) => while_(x.read.eq(nullLiteral).or(z.read.eq(nullLiteral)), [
                  if_(expr('bool'), [
                    x.read.as_('int').stmt,
                    y.read.as_('int').stmt,
                    break_(t),
                  ]),
                ])),
        checkPromoted(x, 'int'),
        checkNotPromoted(y),
        checkNotPromoted(z),
      ]);
    });

    test('Infinite loop does not implicitly assign variables', () {
      var h = Harness();
      var x = Var('x', 'int');
      h.run([
        declare(x, initialized: false),
        while_(booleanLiteral(true), [
          x.write(expr('Null')).stmt,
        ]),
        checkAssigned(x, false),
      ]);
    });

    test('If(false) does not discard promotions', () {
      var h = Harness();
      var x = Var('x', 'Object');
      h.run([
        declare(x, initialized: true),
        x.read.as_('int').stmt,
        checkPromoted(x, 'int'),
        if_(booleanLiteral(false), [
          checkPromoted(x, 'int'),
        ]),
      ]);
    });

    test('Promotions do not occur when a variable is write-captured', () {
      var h = Harness();
      var x = Var('x', 'Object');
      h.run([
        declare(x, initialized: true),
        localFunction([
          x.write(expr('Object')).stmt,
        ]),
        x.read.as_('int').stmt,
        checkNotPromoted(x),
      ]);
    });

    test('Promotion cancellation of write-captured vars survives join', () {
      var h = Harness();
      var x = Var('x', 'Object');
      h.run([
        declare(x, initialized: true),
        if_(expr('bool'), [
          localFunction([
            x.write(expr('Object')).stmt,
          ]),
        ], [
          // Promotion should work here because the write capture is in the
          // other branch.
          x.read.as_('int').stmt, checkPromoted(x, 'int'),
        ]),
        // But the promotion should be cancelled now, after the join.
        checkNotPromoted(x),
        // And further attempts to promote should fail due to the write capture.
        x.read.as_('int').stmt, checkNotPromoted(x),
      ]);
    });
  });

  group('Reachability', () {
    test('initial state', () {
      expect(Reachability.initial.parent, isNull);
      expect(Reachability.initial.locallyReachable, true);
      expect(Reachability.initial.overallReachable, true);
    });

    test('split', () {
      var reachableSplit = Reachability.initial.split();
      expect(reachableSplit.parent, same(Reachability.initial));
      expect(reachableSplit.overallReachable, true);
      expect(reachableSplit.locallyReachable, true);
      var unreachable = reachableSplit.setUnreachable();
      var unreachableSplit = unreachable.split();
      expect(unreachableSplit.parent, same(unreachable));
      expect(unreachableSplit.overallReachable, false);
      expect(unreachableSplit.locallyReachable, true);
    });

    test('unsplit', () {
      var base = Reachability.initial.split();
      var reachableSplit = base.split();
      var reachableSplitUnsplit = reachableSplit.unsplit();
      expect(reachableSplitUnsplit.parent, same(base.parent));
      expect(reachableSplitUnsplit.overallReachable, true);
      expect(reachableSplitUnsplit.locallyReachable, true);
      var reachableSplitUnreachable = reachableSplit.setUnreachable();
      var reachableSplitUnreachableUnsplit =
          reachableSplitUnreachable.unsplit();
      expect(reachableSplitUnreachableUnsplit.parent, same(base.parent));
      expect(reachableSplitUnreachableUnsplit.overallReachable, false);
      expect(reachableSplitUnreachableUnsplit.locallyReachable, false);
      var unreachable = base.setUnreachable();
      var unreachableSplit = unreachable.split();
      var unreachableSplitUnsplit = unreachableSplit.unsplit();
      expect(unreachableSplitUnsplit, same(unreachable));
      var unreachableSplitUnreachable = unreachableSplit.setUnreachable();
      var unreachableSplitUnreachableUnsplit =
          unreachableSplitUnreachable.unsplit();
      expect(unreachableSplitUnreachableUnsplit, same(unreachable));
    });

    test('setUnreachable', () {
      var reachable = Reachability.initial.split();
      var unreachable = reachable.setUnreachable();
      expect(unreachable.parent, same(reachable.parent));
      expect(unreachable.locallyReachable, false);
      expect(unreachable.overallReachable, false);
      expect(unreachable.setUnreachable(), same(unreachable));
      var provisionallyReachable = unreachable.split();
      var provisionallyUnreachable = provisionallyReachable.setUnreachable();
      expect(
          provisionallyUnreachable.parent, same(provisionallyReachable.parent));
      expect(provisionallyUnreachable.locallyReachable, false);
      expect(provisionallyUnreachable.overallReachable, false);
      expect(provisionallyUnreachable.setUnreachable(),
          same(provisionallyUnreachable));
    });

    test('restrict', () {
      var previous = Reachability.initial.split();
      var reachable = previous.split();
      var unreachable = reachable.setUnreachable();
      expect(Reachability.restrict(reachable, reachable), same(reachable));
      expect(Reachability.restrict(reachable, unreachable), same(unreachable));
      expect(Reachability.restrict(unreachable, reachable), same(unreachable));
      expect(
          Reachability.restrict(unreachable, unreachable), same(unreachable));
    });

    test('join', () {
      var previous = Reachability.initial.split();
      var reachable = previous.split();
      var unreachable = reachable.setUnreachable();
      expect(Reachability.join(reachable, reachable), same(reachable));
      expect(Reachability.join(reachable, unreachable), same(reachable));
      expect(Reachability.join(unreachable, reachable), same(reachable));
      expect(Reachability.join(unreachable, unreachable), same(unreachable));
    });
  });

  group('State', () {
    var intVar = Var('x', 'int');
    var intQVar = Var('x', 'int?');
    var objectQVar = Var('x', 'Object?');
    var nullVar = Var('x', 'Null');
    group('setUnreachable', () {
      var unreachable =
          FlowModel<Var, Type>(Reachability.initial.setUnreachable());
      var reachable = FlowModel<Var, Type>(Reachability.initial);
      test('unchanged', () {
        expect(unreachable.setUnreachable(), same(unreachable));
      });

      test('changed', () {
        void _check(FlowModel<Var, Type> initial) {
          var s = initial.setUnreachable();
          expect(s, isNot(same(initial)));
          expect(s.reachable.overallReachable, false);
          expect(s.variableInfo, same(initial.variableInfo));
        }

        _check(reachable);
      });
    });

    test('split', () {
      var s1 = FlowModel<Var, Type>(Reachability.initial);
      var s2 = s1.split();
      expect(s2.reachable.parent, same(s1.reachable));
    });

    test('unsplit', () {
      var s1 = FlowModel<Var, Type>(Reachability.initial.split());
      var s2 = s1.unsplit();
      expect(s2.reachable, same(Reachability.initial));
    });

    group('unsplitTo', () {
      test('no change', () {
        var s1 = FlowModel<Var, Type>(Reachability.initial.split());
        var result = s1.unsplitTo(s1.reachable.parent);
        expect(result, same(s1));
      });

      test('unsplit once, reachable', () {
        var s1 = FlowModel<Var, Type>(Reachability.initial.split());
        var s2 = s1.split();
        var result = s2.unsplitTo(s1.reachable.parent);
        expect(result.reachable, same(s1.reachable));
      });

      test('unsplit once, unreachable', () {
        var s1 = FlowModel<Var, Type>(Reachability.initial.split());
        var s2 = s1.split().setUnreachable();
        var result = s2.unsplitTo(s1.reachable.parent);
        expect(result.reachable.locallyReachable, false);
        expect(result.reachable.parent, same(s1.reachable.parent));
      });

      test('unsplit twice, reachable', () {
        var s1 = FlowModel<Var, Type>(Reachability.initial.split());
        var s2 = s1.split();
        var s3 = s2.split();
        var result = s3.unsplitTo(s1.reachable.parent);
        expect(result.reachable, same(s1.reachable));
      });

      test('unsplit twice, top unreachable', () {
        var s1 = FlowModel<Var, Type>(Reachability.initial.split());
        var s2 = s1.split();
        var s3 = s2.split().setUnreachable();
        var result = s3.unsplitTo(s1.reachable.parent);
        expect(result.reachable.locallyReachable, false);
        expect(result.reachable.parent, same(s1.reachable.parent));
      });

      test('unsplit twice, previous unreachable', () {
        var s1 = FlowModel<Var, Type>(Reachability.initial.split());
        var s2 = s1.split().setUnreachable();
        var s3 = s2.split();
        var result = s3.unsplitTo(s1.reachable.parent);
        expect(result.reachable.locallyReachable, false);
        expect(result.reachable.parent, same(s1.reachable.parent));
      });
    });

    group('tryPromoteForTypeCheck', () {
      test('unpromoted -> unchanged (same)', () {
        var h = Harness();
        var s1 = FlowModel<Var, Type>(Reachability.initial);
        var s2 = s1.tryPromoteForTypeCheck(h, intVar, Type('int')).ifTrue;
        expect(s2, same(s1));
      });

      test('unpromoted -> unchanged (supertype)', () {
        var h = Harness();
        var s1 = FlowModel<Var, Type>(Reachability.initial);
        var s2 = s1.tryPromoteForTypeCheck(h, intVar, Type('Object')).ifTrue;
        expect(s2, same(s1));
      });

      test('unpromoted -> unchanged (unrelated)', () {
        var h = Harness();
        var s1 = FlowModel<Var, Type>(Reachability.initial);
        var s2 = s1.tryPromoteForTypeCheck(h, intVar, Type('String')).ifTrue;
        expect(s2, same(s1));
      });

      test('unpromoted -> subtype', () {
        var h = Harness();
        var s1 = FlowModel<Var, Type>(Reachability.initial);
        var s2 = s1.tryPromoteForTypeCheck(h, intQVar, Type('int')).ifTrue;
        expect(s2.reachable.overallReachable, true);
        expect(s2.variableInfo, {
          intQVar: _matchVariableModel(chain: ['int'], ofInterest: ['int'])
        });
      });

      test('promoted -> unchanged (same)', () {
        var h = Harness();
        var s1 = FlowModel<Var, Type>(Reachability.initial)
            .tryPromoteForTypeCheck(h, objectQVar, Type('int'))
            .ifTrue;
        var s2 = s1.tryPromoteForTypeCheck(h, objectQVar, Type('int')).ifTrue;
        expect(s2, same(s1));
      });

      test('promoted -> unchanged (supertype)', () {
        var h = Harness();
        var s1 = FlowModel<Var, Type>(Reachability.initial)
            .tryPromoteForTypeCheck(h, objectQVar, Type('int'))
            .ifTrue;
        var s2 =
            s1.tryPromoteForTypeCheck(h, objectQVar, Type('Object')).ifTrue;
        expect(s2, same(s1));
      });

      test('promoted -> unchanged (unrelated)', () {
        var h = Harness();
        var s1 = FlowModel<Var, Type>(Reachability.initial)
            .tryPromoteForTypeCheck(h, objectQVar, Type('int'))
            .ifTrue;
        var s2 =
            s1.tryPromoteForTypeCheck(h, objectQVar, Type('String')).ifTrue;
        expect(s2, same(s1));
      });

      test('promoted -> subtype', () {
        var h = Harness();
        var s1 = FlowModel<Var, Type>(Reachability.initial)
            .tryPromoteForTypeCheck(h, objectQVar, Type('int?'))
            .ifTrue;
        var s2 = s1.tryPromoteForTypeCheck(h, objectQVar, Type('int')).ifTrue;
        expect(s2.reachable.overallReachable, true);
        expect(s2.variableInfo, {
          objectQVar: _matchVariableModel(
              chain: ['int?', 'int'], ofInterest: ['int?', 'int'])
        });
      });
    });

    group('write', () {
      var objectQVar = Var('x', 'Object?');

      test('without declaration', () {
        // This should not happen in valid code, but test that we don't crash.
        var h = Harness();
        var s = FlowModel<Var, Type>(Reachability.initial)
            .write(objectQVar, Type('Object?'), h);
        expect(s.variableInfo[objectQVar], isNull);
      });

      test('unchanged', () {
        var h = Harness();
        var s1 = FlowModel<Var, Type>(Reachability.initial)
            .declare(objectQVar, true);
        var s2 = s1.write(objectQVar, Type('Object?'), h);
        expect(s2, same(s1));
      });

      test('marks as assigned', () {
        var h = Harness();
        var s1 = FlowModel<Var, Type>(Reachability.initial)
            .declare(objectQVar, false);
        var s2 = s1.write(objectQVar, Type('int?'), h);
        expect(s2.reachable.overallReachable, true);
        expect(
            s2.infoFor(objectQVar),
            _matchVariableModel(
                chain: null,
                ofInterest: isEmpty,
                assigned: true,
                unassigned: false));
      });

      test('un-promotes fully', () {
        var h = Harness();
        var s1 = FlowModel<Var, Type>(Reachability.initial)
            .declare(objectQVar, true)
            .tryPromoteForTypeCheck(h, objectQVar, Type('int'))
            .ifTrue;
        expect(s1.variableInfo, contains(objectQVar));
        var s2 = s1.write(objectQVar, Type('int?'), h);
        expect(s2.reachable.overallReachable, true);
        expect(s2.variableInfo, {
          objectQVar: _matchVariableModel(
              chain: null,
              ofInterest: isEmpty,
              assigned: true,
              unassigned: false)
        });
      });

      test('un-promotes partially, when no exact match', () {
        var h = Harness();
        var s1 = FlowModel<Var, Type>(Reachability.initial)
            .declare(objectQVar, true)
            .tryPromoteForTypeCheck(h, objectQVar, Type('num?'))
            .ifTrue
            .tryPromoteForTypeCheck(h, objectQVar, Type('int'))
            .ifTrue;
        expect(s1.variableInfo, {
          objectQVar: _matchVariableModel(
              chain: ['num?', 'int'],
              ofInterest: ['num?', 'int'],
              assigned: true,
              unassigned: false)
        });
        var s2 = s1.write(objectQVar, Type('num'), h);
        expect(s2.reachable.overallReachable, true);
        expect(s2.variableInfo, {
          objectQVar: _matchVariableModel(
              chain: ['num?', 'num'],
              ofInterest: ['num?', 'int'],
              assigned: true,
              unassigned: false)
        });
      });

      test('un-promotes partially, when exact match', () {
        var h = Harness();
        var s1 = FlowModel<Var, Type>(Reachability.initial)
            .declare(objectQVar, true)
            .tryPromoteForTypeCheck(h, objectQVar, Type('num?'))
            .ifTrue
            .tryPromoteForTypeCheck(h, objectQVar, Type('num'))
            .ifTrue
            .tryPromoteForTypeCheck(h, objectQVar, Type('int'))
            .ifTrue;
        expect(s1.variableInfo, {
          objectQVar: _matchVariableModel(
              chain: ['num?', 'num', 'int'],
              ofInterest: ['num?', 'num', 'int'],
              assigned: true,
              unassigned: false)
        });
        var s2 = s1.write(objectQVar, Type('num'), h);
        expect(s2.reachable.overallReachable, true);
        expect(s2.variableInfo, {
          objectQVar: _matchVariableModel(
              chain: ['num?', 'num'],
              ofInterest: ['num?', 'num', 'int'],
              assigned: true,
              unassigned: false)
        });
      });

      test('leaves promoted, when exact match', () {
        var h = Harness();
        var s1 = FlowModel<Var, Type>(Reachability.initial)
            .declare(objectQVar, true)
            .tryPromoteForTypeCheck(h, objectQVar, Type('num?'))
            .ifTrue
            .tryPromoteForTypeCheck(h, objectQVar, Type('num'))
            .ifTrue;
        expect(s1.variableInfo, {
          objectQVar: _matchVariableModel(
              chain: ['num?', 'num'],
              ofInterest: ['num?', 'num'],
              assigned: true,
              unassigned: false)
        });
        var s2 = s1.write(objectQVar, Type('num'), h);
        expect(s2.reachable.overallReachable, true);
        expect(s2.variableInfo, same(s1.variableInfo));
      });

      test('leaves promoted, when writing a subtype', () {
        var h = Harness();
        var s1 = FlowModel<Var, Type>(Reachability.initial)
            .declare(objectQVar, true)
            .tryPromoteForTypeCheck(h, objectQVar, Type('num?'))
            .ifTrue
            .tryPromoteForTypeCheck(h, objectQVar, Type('num'))
            .ifTrue;
        expect(s1.variableInfo, {
          objectQVar: _matchVariableModel(
              chain: ['num?', 'num'],
              ofInterest: ['num?', 'num'],
              assigned: true,
              unassigned: false)
        });
        var s2 = s1.write(objectQVar, Type('int'), h);
        expect(s2.reachable.overallReachable, true);
        expect(s2.variableInfo, same(s1.variableInfo));
      });

      group('Promotes to NonNull of a type of interest', () {
        test('when declared type', () {
          var h = Harness();
          var x = Var('x', 'int?');

          var s1 = FlowModel<Var, Type>(Reachability.initial).declare(x, true);
          expect(s1.variableInfo, {
            x: _matchVariableModel(chain: null),
          });

          var s2 = s1.write(x, Type('int'), h);
          expect(s2.variableInfo, {
            x: _matchVariableModel(chain: ['int']),
          });
        });

        test('when declared type, if write-captured', () {
          var h = Harness();
          var x = Var('x', 'int?');

          var s1 = FlowModel<Var, Type>(Reachability.initial).declare(x, true);
          expect(s1.variableInfo, {
            x: _matchVariableModel(chain: null),
          });

          var s2 = s1.conservativeJoin([], [x]);
          expect(s2.variableInfo, {
            x: _matchVariableModel(chain: null, writeCaptured: true),
          });

          // 'x' is write-captured, so not promoted
          var s3 = s2.write(x, Type('int'), h);
          expect(s3.variableInfo, {
            x: _matchVariableModel(chain: null, writeCaptured: true),
          });
        });

        test('when promoted', () {
          var h = Harness();
          var s1 = FlowModel<Var, Type>(Reachability.initial)
              .declare(objectQVar, true)
              .tryPromoteForTypeCheck(h, objectQVar, Type('int?'))
              .ifTrue;
          expect(s1.variableInfo, {
            objectQVar: _matchVariableModel(
              chain: ['int?'],
              ofInterest: ['int?'],
            ),
          });
          var s2 = s1.write(objectQVar, Type('int'), h);
          expect(s2.variableInfo, {
            objectQVar: _matchVariableModel(
              chain: ['int?', 'int'],
              ofInterest: ['int?'],
            ),
          });
        });

        test('when not promoted', () {
          var h = Harness();
          var s1 = FlowModel<Var, Type>(Reachability.initial)
              .declare(objectQVar, true)
              .tryPromoteForTypeCheck(h, objectQVar, Type('int?'))
              .ifFalse;
          expect(s1.variableInfo, {
            objectQVar: _matchVariableModel(
              chain: ['Object'],
              ofInterest: ['int?'],
            ),
          });
          var s2 = s1.write(objectQVar, Type('int'), h);
          expect(s2.variableInfo, {
            objectQVar: _matchVariableModel(
              chain: ['Object', 'int'],
              ofInterest: ['int?'],
            ),
          });
        });
      });

      test('Promotes to type of interest when not previously promoted', () {
        var h = Harness();
        var s1 = FlowModel<Var, Type>(Reachability.initial)
            .declare(objectQVar, true)
            .tryPromoteForTypeCheck(h, objectQVar, Type('num?'))
            .ifFalse;
        expect(s1.variableInfo, {
          objectQVar: _matchVariableModel(
            chain: ['Object'],
            ofInterest: ['num?'],
          ),
        });
        var s2 = s1.write(objectQVar, Type('num?'), h);
        expect(s2.variableInfo, {
          objectQVar: _matchVariableModel(
            chain: ['num?'],
            ofInterest: ['num?'],
          ),
        });
      });

      test('Promotes to type of interest when previously promoted', () {
        var h = Harness();
        var s1 = FlowModel<Var, Type>(Reachability.initial)
            .declare(objectQVar, true)
            .tryPromoteForTypeCheck(h, objectQVar, Type('num?'))
            .ifTrue
            .tryPromoteForTypeCheck(h, objectQVar, Type('int?'))
            .ifFalse;
        expect(s1.variableInfo, {
          objectQVar: _matchVariableModel(
            chain: ['num?', 'num'],
            ofInterest: ['num?', 'int?'],
          ),
        });
        var s2 = s1.write(objectQVar, Type('int?'), h);
        expect(s2.variableInfo, {
          objectQVar: _matchVariableModel(
            chain: ['num?', 'int?'],
            ofInterest: ['num?', 'int?'],
          ),
        });
      });

      group('Multiple candidate types of interest', () {
        group('; choose most specific', () {
          Harness h;

          setUp(() {
            h = Harness();

            // class A {}
            // class B extends A {}
            // class C extends B {}
            h.addSubtype(Type('Object'), Type('A'), false);
            h.addSubtype(Type('Object'), Type('A?'), false);
            h.addSubtype(Type('Object'), Type('B?'), false);
            h.addSubtype(Type('A'), Type('Object'), true);
            h.addSubtype(Type('A'), Type('Object?'), true);
            h.addSubtype(Type('A'), Type('A?'), true);
            h.addSubtype(Type('A'), Type('B'), false);
            h.addSubtype(Type('A'), Type('B?'), false);
            h.addSubtype(Type('A?'), Type('Object'), false);
            h.addSubtype(Type('A?'), Type('Object?'), true);
            h.addSubtype(Type('A?'), Type('A'), false);
            h.addSubtype(Type('A?'), Type('B?'), false);
            h.addSubtype(Type('B'), Type('Object'), true);
            h.addSubtype(Type('B'), Type('A'), true);
            h.addSubtype(Type('B'), Type('A?'), true);
            h.addSubtype(Type('B'), Type('B?'), true);
            h.addSubtype(Type('B?'), Type('Object'), false);
            h.addSubtype(Type('B?'), Type('Object?'), true);
            h.addSubtype(Type('B?'), Type('A'), false);
            h.addSubtype(Type('B?'), Type('A?'), true);
            h.addSubtype(Type('B?'), Type('B'), false);
            h.addSubtype(Type('C'), Type('Object'), true);
            h.addSubtype(Type('C'), Type('A'), true);
            h.addSubtype(Type('C'), Type('A?'), true);
            h.addSubtype(Type('C'), Type('B'), true);
            h.addSubtype(Type('C'), Type('B?'), true);

            h.addFactor(Type('Object'), Type('A?'), Type('Object'));
            h.addFactor(Type('Object'), Type('B?'), Type('Object'));
            h.addFactor(Type('Object?'), Type('A'), Type('Object?'));
            h.addFactor(Type('Object?'), Type('A?'), Type('Object'));
            h.addFactor(Type('Object?'), Type('B?'), Type('Object'));
          });

          test('; first', () {
            var x = Var('x', 'Object?');

            var s1 = FlowModel<Var, Type>(Reachability.initial)
                .declare(x, true)
                .tryPromoteForTypeCheck(h, x, Type('B?'))
                .ifFalse
                .tryPromoteForTypeCheck(h, x, Type('A?'))
                .ifFalse;
            expect(s1.variableInfo, {
              x: _matchVariableModel(
                chain: ['Object'],
                ofInterest: ['A?', 'B?'],
              ),
            });

            var s2 = s1.write(x, Type('C'), h);
            expect(s2.variableInfo, {
              x: _matchVariableModel(
                chain: ['Object', 'B'],
                ofInterest: ['A?', 'B?'],
              ),
            });
          });

          test('; second', () {
            var x = Var('x', 'Object?');

            var s1 = FlowModel<Var, Type>(Reachability.initial)
                .declare(x, true)
                .tryPromoteForTypeCheck(h, x, Type('A?'))
                .ifFalse
                .tryPromoteForTypeCheck(h, x, Type('B?'))
                .ifFalse;
            expect(s1.variableInfo, {
              x: _matchVariableModel(
                chain: ['Object'],
                ofInterest: ['A?', 'B?'],
              ),
            });

            var s2 = s1.write(x, Type('C'), h);
            expect(s2.variableInfo, {
              x: _matchVariableModel(
                chain: ['Object', 'B'],
                ofInterest: ['A?', 'B?'],
              ),
            });
          });

          test('; nullable and non-nullable', () {
            var x = Var('x', 'Object?');

            var s1 = FlowModel<Var, Type>(Reachability.initial)
                .declare(x, true)
                .tryPromoteForTypeCheck(h, x, Type('A'))
                .ifFalse
                .tryPromoteForTypeCheck(h, x, Type('A?'))
                .ifFalse;
            expect(s1.variableInfo, {
              x: _matchVariableModel(
                chain: ['Object'],
                ofInterest: ['A', 'A?'],
              ),
            });

            var s2 = s1.write(x, Type('B'), h);
            expect(s2.variableInfo, {
              x: _matchVariableModel(
                chain: ['Object', 'A'],
                ofInterest: ['A', 'A?'],
              ),
            });
          });
        });

        group('; ambiguous', () {
          test('; no promotion', () {
            var h = Harness();
            var s1 = FlowModel<Var, Type>(Reachability.initial)
                .declare(objectQVar, true)
                .tryPromoteForTypeCheck(h, objectQVar, Type('num?'))
                .ifFalse
                .tryPromoteForTypeCheck(h, objectQVar, Type('num*'))
                .ifFalse;
            expect(s1.variableInfo, {
              objectQVar: _matchVariableModel(
                chain: ['Object'],
                ofInterest: ['num?', 'num*'],
              ),
            });
            var s2 = s1.write(objectQVar, Type('int'), h);
            // It's ambiguous whether to promote to num? or num*, so we don't
            // promote.
            expect(s2, same(s1));
          });
        });

        test('exact match', () {
          var h = Harness();
          var s1 = FlowModel<Var, Type>(Reachability.initial)
              .declare(objectQVar, true)
              .tryPromoteForTypeCheck(h, objectQVar, Type('num?'))
              .ifFalse
              .tryPromoteForTypeCheck(h, objectQVar, Type('num*'))
              .ifFalse;
          expect(s1.variableInfo, {
            objectQVar: _matchVariableModel(
              chain: ['Object'],
              ofInterest: ['num?', 'num*'],
            ),
          });
          var s2 = s1.write(objectQVar, Type('num?'), h);
          // It's ambiguous whether to promote to num? or num*, but since the
          // written type is exactly num?, we use that.
          expect(s2.variableInfo, {
            objectQVar: _matchVariableModel(
              chain: ['num?'],
              ofInterest: ['num?', 'num*'],
            ),
          });
        });
      });
    });

    group('demotion, to NonNull', () {
      test('when promoted via test', () {
        var x = Var('x', 'Object?');

        var h = Harness();

        var s1 = FlowModel<Var, Type>(Reachability.initial)
            .declare(x, true)
            .tryPromoteForTypeCheck(h, x, Type('num?'))
            .ifTrue
            .tryPromoteForTypeCheck(h, x, Type('int?'))
            .ifTrue;
        expect(s1.variableInfo, {
          x: _matchVariableModel(
            chain: ['num?', 'int?'],
            ofInterest: ['num?', 'int?'],
          ),
        });

        var s2 = s1.write(x, Type('double'), h);
        expect(s2.variableInfo, {
          x: _matchVariableModel(
            chain: ['num?', 'num'],
            ofInterest: ['num?', 'int?'],
          ),
        });
      });
    });

    group('declare', () {
      var objectQVar = Var('x', 'Object?');

      test('initialized', () {
        var s = FlowModel<Var, Type>(Reachability.initial)
            .declare(objectQVar, true);
        expect(s.variableInfo, {
          objectQVar: _matchVariableModel(assigned: true, unassigned: false),
        });
      });

      test('not initialized', () {
        var s = FlowModel<Var, Type>(Reachability.initial)
            .declare(objectQVar, false);
        expect(s.variableInfo, {
          objectQVar: _matchVariableModel(assigned: false, unassigned: true),
        });
      });
    });

    group('markNonNullable', () {
      test('unpromoted -> unchanged', () {
        var h = Harness();
        var s1 = FlowModel<Var, Type>(Reachability.initial);
        var s2 = s1.tryMarkNonNullable(h, intVar).ifTrue;
        expect(s2, same(s1));
      });

      test('unpromoted -> promoted', () {
        var h = Harness();
        var s1 = FlowModel<Var, Type>(Reachability.initial);
        var s2 = s1.tryMarkNonNullable(h, intQVar).ifTrue;
        expect(s2.reachable.overallReachable, true);
        expect(s2.infoFor(intQVar),
            _matchVariableModel(chain: ['int'], ofInterest: []));
      });

      test('promoted -> unchanged', () {
        var h = Harness();
        var s1 = FlowModel<Var, Type>(Reachability.initial)
            .tryPromoteForTypeCheck(h, objectQVar, Type('int'))
            .ifTrue;
        var s2 = s1.tryMarkNonNullable(h, objectQVar).ifTrue;
        expect(s2, same(s1));
      });

      test('promoted -> re-promoted', () {
        var h = Harness();
        var s1 = FlowModel<Var, Type>(Reachability.initial)
            .tryPromoteForTypeCheck(h, objectQVar, Type('int?'))
            .ifTrue;
        var s2 = s1.tryMarkNonNullable(h, objectQVar).ifTrue;
        expect(s2.reachable.overallReachable, true);
        expect(s2.variableInfo, {
          objectQVar:
              _matchVariableModel(chain: ['int?', 'int'], ofInterest: ['int?'])
        });
      });

      test('promote to Never', () {
        var h = Harness();
        var s1 = FlowModel<Var, Type>(Reachability.initial);
        var s2 = s1.tryMarkNonNullable(h, nullVar).ifTrue;
        expect(s2.reachable.overallReachable, false);
        expect(s2.infoFor(nullVar),
            _matchVariableModel(chain: ['Never'], ofInterest: []));
      });
    });

    group('conservativeJoin', () {
      test('unchanged', () {
        var h = Harness();
        var s1 = FlowModel<Var, Type>(Reachability.initial)
            .declare(intQVar, true)
            .tryPromoteForTypeCheck(h, objectQVar, Type('int'))
            .ifTrue;
        var s2 = s1.conservativeJoin([intQVar], []);
        expect(s2, same(s1));
      });

      test('written', () {
        var h = Harness();
        var s1 = FlowModel<Var, Type>(Reachability.initial)
            .tryPromoteForTypeCheck(h, objectQVar, Type('int'))
            .ifTrue
            .tryPromoteForTypeCheck(h, intQVar, Type('int'))
            .ifTrue;
        var s2 = s1.conservativeJoin([intQVar], []);
        expect(s2.reachable.overallReachable, true);
        expect(s2.variableInfo, {
          objectQVar: _matchVariableModel(chain: ['int'], ofInterest: ['int']),
          intQVar: _matchVariableModel(chain: null, ofInterest: ['int'])
        });
      });

      test('write captured', () {
        var h = Harness();
        var s1 = FlowModel<Var, Type>(Reachability.initial)
            .tryPromoteForTypeCheck(h, objectQVar, Type('int'))
            .ifTrue
            .tryPromoteForTypeCheck(h, intQVar, Type('int'))
            .ifTrue;
        var s2 = s1.conservativeJoin([], [intQVar]);
        expect(s2.reachable.overallReachable, true);
        expect(s2.variableInfo, {
          objectQVar: _matchVariableModel(chain: ['int'], ofInterest: ['int']),
          intQVar: _matchVariableModel(
              chain: null, ofInterest: isEmpty, unassigned: false)
        });
      });
    });

    group('restrict', () {
      test('reachability', () {
        var h = Harness();
        var reachable = FlowModel<Var, Type>(Reachability.initial);
        var unreachable = reachable.setUnreachable();
        expect(reachable.restrict(h, reachable, Set()), same(reachable));
        expect(reachable.restrict(h, unreachable, Set()), same(unreachable));
        expect(unreachable.restrict(h, reachable, Set()), same(unreachable));
        expect(unreachable.restrict(h, unreachable, Set()), same(unreachable));
      });

      test('assignments', () {
        var h = Harness();
        var a = Var('a', 'int');
        var b = Var('b', 'int');
        var c = Var('c', 'int');
        var d = Var('d', 'int');
        var s0 = FlowModel<Var, Type>(Reachability.initial)
            .declare(a, false)
            .declare(b, false)
            .declare(c, false)
            .declare(d, false);
        var s1 = s0.write(a, Type('int'), h).write(b, Type('int'), h);
        var s2 = s1.write(a, Type('int'), h).write(c, Type('int'), h);
        var result = s2.restrict(h, s1, Set());
        expect(result.infoFor(a).assigned, true);
        expect(result.infoFor(b).assigned, true);
        expect(result.infoFor(c).assigned, true);
        expect(result.infoFor(d).assigned, false);
      });

      test('write captured', () {
        var h = Harness();
        var a = Var('a', 'int');
        var b = Var('b', 'int');
        var c = Var('c', 'int');
        var d = Var('d', 'int');
        var s0 = FlowModel<Var, Type>(Reachability.initial)
            .declare(a, false)
            .declare(b, false)
            .declare(c, false)
            .declare(d, false);
        // In s1, a and b are write captured.  In s2, a and c are.
        var s1 = s0.conservativeJoin([a, b], [a, b]);
        var s2 = s1.conservativeJoin([a, c], [a, c]);
        var result = s2.restrict(h, s1, Set());
        expect(
          result.infoFor(a),
          _matchVariableModel(writeCaptured: true, unassigned: false),
        );
        expect(
          result.infoFor(b),
          _matchVariableModel(writeCaptured: true, unassigned: false),
        );
        expect(
          result.infoFor(c),
          _matchVariableModel(writeCaptured: true, unassigned: false),
        );
        expect(
          result.infoFor(d),
          _matchVariableModel(writeCaptured: false, unassigned: true),
        );
      });

      test('promotion', () {
        void _check(String thisType, String otherType, bool unsafe,
            List<String> expectedChain) {
          var h = Harness();
          var x = Var('x', 'Object?');
          var s0 = FlowModel<Var, Type>(Reachability.initial).declare(x, true);
          var s1 = thisType == null
              ? s0
              : s0.tryPromoteForTypeCheck(h, x, Type(thisType)).ifTrue;
          var s2 = otherType == null
              ? s0
              : s0.tryPromoteForTypeCheck(h, x, Type(otherType)).ifTrue;
          var result = s1.restrict(h, s2, unsafe ? [x].toSet() : Set());
          if (expectedChain == null) {
            expect(result.variableInfo, contains(x));
            expect(result.infoFor(x).promotedTypes, isNull);
          } else {
            expect(result.infoFor(x).promotedTypes.map((t) => t.type).toList(),
                expectedChain);
          }
        }

        _check(null, null, false, null);
        _check(null, null, true, null);
        _check('int', null, false, ['int']);
        _check('int', null, true, ['int']);
        _check(null, 'int', false, ['int']);
        _check(null, 'int', true, null);
        _check('int?', 'int', false, ['int']);
        _check('int', 'int?', false, ['int?', 'int']);
        _check('int', 'String', false, ['String']);
        _check('int?', 'int', true, ['int?']);
        _check('int', 'int?', true, ['int']);
        _check('int', 'String', true, ['int']);
      });

      test('promotion chains', () {
        // Verify that the given promotion chain matches the expected list of
        // strings.
        void _checkChain(List<Type> chain, List<String> expected) {
          var strings = (chain ?? <Type>[]).map((t) => t.type).toList();
          expect(strings, expected);
        }

        // Test the following scenario:
        // - Prior to the try/finally block, the sequence of promotions in
        //   [before] is done.
        // - During the try block, the sequence of promotions in [inTry] is
        //   done.
        // - During the finally block, the sequence of promotions in
        //   [inFinally] is done.
        // - After calling `restrict` to refine the state from the finally
        //   block, the expected promotion chain is [expectedResult].
        void _check(List<String> before, List<String> inTry,
            List<String> inFinally, List<String> expectedResult) {
          var h = Harness();
          var x = Var('x', 'Object?');
          var initialModel =
              FlowModel<Var, Type>(Reachability.initial).declare(x, true);
          for (var t in before) {
            initialModel =
                initialModel.tryPromoteForTypeCheck(h, x, Type(t)).ifTrue;
          }
          _checkChain(initialModel.infoFor(x).promotedTypes, before);
          var tryModel = initialModel;
          for (var t in inTry) {
            tryModel = tryModel.tryPromoteForTypeCheck(h, x, Type(t)).ifTrue;
          }
          var expectedTryChain = before.toList()..addAll(inTry);
          _checkChain(tryModel.infoFor(x).promotedTypes, expectedTryChain);
          var finallyModel = initialModel;
          for (var t in inFinally) {
            finallyModel =
                finallyModel.tryPromoteForTypeCheck(h, x, Type(t)).ifTrue;
          }
          var expectedFinallyChain = before.toList()..addAll(inFinally);
          _checkChain(
              finallyModel.infoFor(x).promotedTypes, expectedFinallyChain);
          var result = finallyModel.restrict(h, tryModel, {});
          _checkChain(result.infoFor(x).promotedTypes, expectedResult);
          // And verify that the inputs are unchanged.
          _checkChain(initialModel.infoFor(x).promotedTypes, before);
          _checkChain(tryModel.infoFor(x).promotedTypes, expectedTryChain);
          _checkChain(
              finallyModel.infoFor(x).promotedTypes, expectedFinallyChain);
        }

        _check(['Object'], ['Iterable', 'List'], ['num', 'int'],
            ['Object', 'Iterable', 'List']);
        _check([], ['Iterable', 'List'], ['num', 'int'], ['Iterable', 'List']);
        _check(['Object'], ['Iterable', 'List'], [],
            ['Object', 'Iterable', 'List']);
        _check([], ['Iterable', 'List'], [], ['Iterable', 'List']);
        _check(['Object'], [], ['num', 'int'], ['Object', 'num', 'int']);
        _check([], [], ['num', 'int'], ['num', 'int']);
        _check(['Object'], [], [], ['Object']);
        _check([], [], [], []);
        _check(
            [], ['Object', 'Iterable'], ['num', 'int'], ['Object', 'Iterable']);
        _check([], ['Object'], ['num', 'int'], ['Object', 'num', 'int']);
        _check([], ['num', 'int'], ['Object', 'Iterable'], ['num', 'int']);
        _check([], ['num', 'int'], ['Object'], ['num', 'int']);
        _check([], ['Object', 'int'], ['num'], ['Object', 'int']);
        _check([], ['Object', 'num'], ['int'], ['Object', 'num', 'int']);
        _check([], ['num'], ['Object', 'int'], ['num', 'int']);
        _check([], ['int'], ['Object', 'num'], ['int']);
      });

      test('variable present in one state but not the other', () {
        var h = Harness();
        var x = Var('x', 'Object?');
        var s0 = FlowModel<Var, Type>(Reachability.initial);
        var s1 = s0.declare(x, true);
        expect(s0.restrict(h, s1, {}), same(s0));
        expect(s0.restrict(h, s1, {x}), same(s0));
        expect(s1.restrict(h, s0, {}), same(s0));
        expect(s1.restrict(h, s0, {x}), same(s0));
      });
    });
  });

  group('joinPromotionChains', () {
    var doubleType = Type('double');
    var intType = Type('int');
    var numType = Type('num');
    var objectType = Type('Object');

    test('should handle nulls', () {
      var h = Harness();
      expect(VariableModel.joinPromotedTypes(null, null, h), null);
      expect(VariableModel.joinPromotedTypes(null, [intType], h), null);
      expect(VariableModel.joinPromotedTypes([intType], null, h), null);
    });

    test('should return null if there are no common types', () {
      var h = Harness();
      expect(VariableModel.joinPromotedTypes([intType], [doubleType], h), null);
    });

    test('should return common prefix if there are common types', () {
      var h = Harness();
      expect(
          VariableModel.joinPromotedTypes(
              [objectType, intType], [objectType, doubleType], h),
          _matchPromotionChain(['Object']));
      expect(
          VariableModel.joinPromotedTypes([objectType, numType, intType],
              [objectType, numType, doubleType], h),
          _matchPromotionChain(['Object', 'num']));
    });

    test('should return an input if it is a prefix of the other', () {
      var h = Harness();
      var prefix = [objectType, numType];
      var largerChain = [objectType, numType, intType];
      expect(VariableModel.joinPromotedTypes(prefix, largerChain, h),
          same(prefix));
      expect(VariableModel.joinPromotedTypes(largerChain, prefix, h),
          same(prefix));
      expect(VariableModel.joinPromotedTypes(prefix, prefix, h), same(prefix));
    });

    test('should intersect', () {
      var h = Harness();

      // F <: E <: D <: C <: B <: A
      var A = Type('A');
      var B = Type('B');
      var C = Type('C');
      var D = Type('D');
      var E = Type('E');
      var F = Type('F');
      h.addSubtype(A, B, false);
      h.addSubtype(B, A, true);
      h.addSubtype(B, C, false);
      h.addSubtype(B, D, false);
      h.addSubtype(C, B, true);
      h.addSubtype(C, D, false);
      h.addSubtype(C, E, false);
      h.addSubtype(D, B, true);
      h.addSubtype(D, C, true);
      h.addSubtype(D, E, false);
      h.addSubtype(D, F, false);
      h.addSubtype(E, C, true);
      h.addSubtype(E, D, true);
      h.addSubtype(E, F, false);
      h.addSubtype(F, D, true);
      h.addSubtype(F, E, true);

      void check(List<Type> chain1, List<Type> chain2, Matcher matcher) {
        expect(
          VariableModel.joinPromotedTypes(chain1, chain2, h),
          matcher,
        );

        expect(
          VariableModel.joinPromotedTypes(chain2, chain1, h),
          matcher,
        );
      }

      {
        var chain1 = [A, B, C];
        var chain2 = [A, C];
        check(chain1, chain2, same(chain2));
      }

      check(
        [A, B, C, F],
        [A, D, E, F],
        _matchPromotionChain(['A', 'F']),
      );

      check(
        [A, B, E, F],
        [A, C, D, F],
        _matchPromotionChain(['A', 'F']),
      );

      check(
        [A, C, E],
        [B, C, D],
        _matchPromotionChain(['C']),
      );

      check(
        [A, C, E, F],
        [B, C, D, F],
        _matchPromotionChain(['C', 'F']),
      );

      check(
        [A, B, C],
        [A, B, D],
        _matchPromotionChain(['A', 'B']),
      );
    });
  });

  group('joinTypesOfInterest', () {
    List<Type> _makeTypes(List<String> typeNames) =>
        typeNames.map((t) => Type(t)).toList();

    test('simple prefix', () {
      var h = Harness();
      var s1 = _makeTypes(['double', 'int']);
      var s2 = _makeTypes(['double', 'int', 'bool']);
      var expected = _matchOfInterestSet(['double', 'int', 'bool']);
      expect(VariableModel.joinTested(s1, s2, h), expected);
      expect(VariableModel.joinTested(s2, s1, h), expected);
    });

    test('common prefix', () {
      var h = Harness();
      var s1 = _makeTypes(['double', 'int', 'String']);
      var s2 = _makeTypes(['double', 'int', 'bool']);
      var expected = _matchOfInterestSet(['double', 'int', 'String', 'bool']);
      expect(VariableModel.joinTested(s1, s2, h), expected);
      expect(VariableModel.joinTested(s2, s1, h), expected);
    });

    test('order mismatch', () {
      var h = Harness();
      var s1 = _makeTypes(['double', 'int']);
      var s2 = _makeTypes(['int', 'double']);
      var expected = _matchOfInterestSet(['double', 'int']);
      expect(VariableModel.joinTested(s1, s2, h), expected);
      expect(VariableModel.joinTested(s2, s1, h), expected);
    });

    test('small common prefix', () {
      var h = Harness();
      var s1 = _makeTypes(['int', 'double', 'String', 'bool']);
      var s2 = _makeTypes(['int', 'List', 'bool', 'Future']);
      var expected = _matchOfInterestSet(
          ['int', 'double', 'String', 'bool', 'List', 'Future']);
      expect(VariableModel.joinTested(s1, s2, h), expected);
      expect(VariableModel.joinTested(s2, s1, h), expected);
    });
  });

  group('join', () {
    var x = Var('x', 'Object?');
    var y = Var('y', 'Object?');
    var z = Var('z', 'Object?');
    var w = Var('w', 'Object?');
    var intType = Type('int');
    var intQType = Type('int?');
    var stringType = Type('String');
    const emptyMap = const <Var, VariableModel<Var, Type>>{};

    VariableModel<Var, Type> model(List<Type> promotionChain,
            {List<Type> typesOfInterest, bool assigned = false}) =>
        VariableModel<Var, Type>(
          promotionChain,
          typesOfInterest ?? promotionChain ?? [],
          assigned,
          !assigned,
          false,
        );

    group('without input reuse', () {
      test('promoted with unpromoted', () {
        var h = Harness();
        var p1 = {
          x: model([intType]),
          y: model(null)
        };
        var p2 = {
          x: model(null),
          y: model([intType])
        };
        expect(FlowModel.joinVariableInfo(h, p1, p2, emptyMap), {
          x: _matchVariableModel(chain: null, ofInterest: ['int']),
          y: _matchVariableModel(chain: null, ofInterest: ['int'])
        });
      });
    });
    group('should re-use an input if possible', () {
      test('identical inputs', () {
        var h = Harness();
        var p = {
          x: model([intType]),
          y: model([stringType])
        };
        expect(FlowModel.joinVariableInfo(h, p, p, emptyMap), same(p));
      });

      test('one input empty', () {
        var h = Harness();
        var p1 = {
          x: model([intType]),
          y: model([stringType])
        };
        var p2 = <Var, VariableModel<Var, Type>>{};
        expect(FlowModel.joinVariableInfo(h, p1, p2, emptyMap), same(emptyMap));
        expect(FlowModel.joinVariableInfo(h, p2, p1, emptyMap), same(emptyMap));
      });

      test('promoted with unpromoted', () {
        var h = Harness();
        var p1 = {
          x: model([intType])
        };
        var p2 = {x: model(null)};
        var expected = {
          x: _matchVariableModel(chain: null, ofInterest: ['int'])
        };
        expect(FlowModel.joinVariableInfo(h, p1, p2, emptyMap), expected);
        expect(FlowModel.joinVariableInfo(h, p2, p1, emptyMap), expected);
      });

      test('related type chains', () {
        var h = Harness();
        var p1 = {
          x: model([intQType, intType])
        };
        var p2 = {
          x: model([intQType])
        };
        var expected = {
          x: _matchVariableModel(chain: ['int?'], ofInterest: ['int?', 'int'])
        };
        expect(FlowModel.joinVariableInfo(h, p1, p2, emptyMap), expected);
        expect(FlowModel.joinVariableInfo(h, p2, p1, emptyMap), expected);
      });

      test('unrelated type chains', () {
        var h = Harness();
        var p1 = {
          x: model([intType])
        };
        var p2 = {
          x: model([stringType])
        };
        var expected = {
          x: _matchVariableModel(chain: null, ofInterest: ['String', 'int'])
        };
        expect(FlowModel.joinVariableInfo(h, p1, p2, emptyMap), expected);
        expect(FlowModel.joinVariableInfo(h, p2, p1, emptyMap), expected);
      });

      test('sub-map', () {
        var h = Harness();
        var xModel = model([intType]);
        var p1 = {
          x: xModel,
          y: model([stringType])
        };
        var p2 = {x: xModel};
        expect(FlowModel.joinVariableInfo(h, p1, p2, emptyMap), same(p2));
        expect(FlowModel.joinVariableInfo(h, p2, p1, emptyMap), same(p2));
      });

      test('sub-map with matched subtype', () {
        var h = Harness();
        var p1 = {
          x: model([intQType, intType]),
          y: model([stringType])
        };
        var p2 = {
          x: model([intQType])
        };
        var expected = {
          x: _matchVariableModel(chain: ['int?'], ofInterest: ['int?', 'int'])
        };
        expect(FlowModel.joinVariableInfo(h, p1, p2, emptyMap), expected);
        expect(FlowModel.joinVariableInfo(h, p2, p1, emptyMap), expected);
      });

      test('sub-map with mismatched subtype', () {
        var h = Harness();
        var p1 = {
          x: model([intQType]),
          y: model([stringType])
        };
        var p2 = {
          x: model([intQType, intType])
        };
        var expected = {
          x: _matchVariableModel(chain: ['int?'], ofInterest: ['int?', 'int'])
        };
        expect(FlowModel.joinVariableInfo(h, p1, p2, emptyMap), expected);
        expect(FlowModel.joinVariableInfo(h, p2, p1, emptyMap), expected);
      });

      test('assigned', () {
        var h = Harness();
        var unassigned = model(null, assigned: false);
        var assigned = model(null, assigned: true);
        var p1 = {x: assigned, y: assigned, z: unassigned, w: unassigned};
        var p2 = {x: assigned, y: unassigned, z: assigned, w: unassigned};
        var joined = FlowModel.joinVariableInfo(h, p1, p2, emptyMap);
        expect(joined, {
          x: same(assigned),
          y: _matchVariableModel(
              chain: null, assigned: false, unassigned: false),
          z: _matchVariableModel(
              chain: null, assigned: false, unassigned: false),
          w: same(unassigned)
        });
      });

      test('write captured', () {
        var h = Harness();
        var intQModel = model([intQType]);
        var writeCapturedModel = intQModel.writeCapture();
        var p1 = {
          x: writeCapturedModel,
          y: writeCapturedModel,
          z: intQModel,
          w: intQModel
        };
        var p2 = {
          x: writeCapturedModel,
          y: intQModel,
          z: writeCapturedModel,
          w: intQModel
        };
        var joined = FlowModel.joinVariableInfo(h, p1, p2, emptyMap);
        expect(joined, {
          x: same(writeCapturedModel),
          y: same(writeCapturedModel),
          z: same(writeCapturedModel),
          w: same(intQModel)
        });
      });
    });
  });

  group('merge', () {
    var x = Var('x', 'Object?');
    var intType = Type('int');
    var stringType = Type('String');
    const emptyMap = const <Var, VariableModel<Var, Type>>{};

    VariableModel<Var, Type> varModel(List<Type> promotionChain,
            {bool assigned = false}) =>
        VariableModel<Var, Type>(
          promotionChain,
          promotionChain ?? [],
          assigned,
          !assigned,
          false,
        );

    test('first is null', () {
      var h = Harness();
      var s1 = FlowModel.withInfo(Reachability.initial.split(), {});
      var result = FlowModel.merge(h, null, s1, emptyMap);
      expect(result.reachable, same(Reachability.initial));
    });

    test('second is null', () {
      var h = Harness();
      var splitPoint = Reachability.initial.split();
      var afterSplit = splitPoint.split();
      var s1 = FlowModel.withInfo(afterSplit, {});
      var result = FlowModel.merge(h, s1, null, emptyMap);
      expect(result.reachable, same(splitPoint));
    });

    test('both are reachable', () {
      var h = Harness();
      var splitPoint = Reachability.initial.split();
      var afterSplit = splitPoint.split();
      var s1 = FlowModel.withInfo(afterSplit, {
        x: varModel([intType])
      });
      var s2 = FlowModel.withInfo(afterSplit, {
        x: varModel([stringType])
      });
      var result = FlowModel.merge(h, s1, s2, emptyMap);
      expect(result.reachable, same(splitPoint));
      expect(result.variableInfo[x].promotedTypes, isNull);
    });

    test('first is unreachable', () {
      var h = Harness();
      var splitPoint = Reachability.initial.split();
      var afterSplit = splitPoint.split();
      var s1 = FlowModel.withInfo(afterSplit.setUnreachable(), {
        x: varModel([intType])
      });
      var s2 = FlowModel.withInfo(afterSplit, {
        x: varModel([stringType])
      });
      var result = FlowModel.merge(h, s1, s2, emptyMap);
      expect(result.reachable, same(splitPoint));
      expect(result.variableInfo, same(s2.variableInfo));
    });

    test('second is unreachable', () {
      var h = Harness();
      var splitPoint = Reachability.initial.split();
      var afterSplit = splitPoint.split();
      var s1 = FlowModel.withInfo(afterSplit, {
        x: varModel([intType])
      });
      var s2 = FlowModel.withInfo(afterSplit.setUnreachable(), {
        x: varModel([stringType])
      });
      var result = FlowModel.merge(h, s1, s2, emptyMap);
      expect(result.reachable, same(splitPoint));
      expect(result.variableInfo, same(s1.variableInfo));
    });

    test('both are unreachable', () {
      var h = Harness();
      var splitPoint = Reachability.initial.split();
      var afterSplit = splitPoint.split();
      var s1 = FlowModel.withInfo(afterSplit.setUnreachable(), {
        x: varModel([intType])
      });
      var s2 = FlowModel.withInfo(afterSplit.setUnreachable(), {
        x: varModel([stringType])
      });
      var result = FlowModel.merge(h, s1, s2, emptyMap);
      expect(result.reachable.locallyReachable, false);
      expect(result.reachable.parent, same(splitPoint.parent));
      expect(result.variableInfo[x].promotedTypes, isNull);
    });
  });

  group('inheritTested', () {
    var x = Var('x', 'Object?');
    var intType = Type('int');
    var stringType = Type('String');
    const emptyMap = const <Var, VariableModel<Var, Type>>{};

    VariableModel<Var, Type> model(List<Type> typesOfInterest) =>
        VariableModel<Var, Type>(null, typesOfInterest, true, false, false);

    test('inherits types of interest from other', () {
      var h = Harness();
      var m1 = FlowModel.withInfo(Reachability.initial, {
        x: model([intType])
      });
      var m2 = FlowModel.withInfo(Reachability.initial, {
        x: model([stringType])
      });
      expect(m1.inheritTested(h, m2).variableInfo[x].tested,
          _matchOfInterestSet(['int', 'String']));
    });

    test('handles variable missing from other', () {
      var h = Harness();
      var m1 = FlowModel.withInfo(Reachability.initial, {
        x: model([intType])
      });
      var m2 = FlowModel.withInfo(Reachability.initial, emptyMap);
      expect(m1.inheritTested(h, m2), same(m1));
    });

    test('returns identical model when no changes', () {
      var h = Harness();
      var m1 = FlowModel.withInfo(Reachability.initial, {
        x: model([intType])
      });
      var m2 = FlowModel.withInfo(Reachability.initial, {
        x: model([intType])
      });
      expect(m1.inheritTested(h, m2), same(m1));
    });
  });
}

/// Returns the appropriate matcher for expecting an assertion error to be
/// thrown or not, based on whether assertions are enabled.
Matcher get _asserts {
  var matcher = throwsA(TypeMatcher<AssertionError>());
  bool assertionsEnabled = false;
  assert(assertionsEnabled = true);
  if (!assertionsEnabled) {
    matcher = isNot(matcher);
  }
  return matcher;
}

String _describeMatcher(Matcher matcher) {
  var description = StringDescription();
  matcher.describe(description);
  return description.toString();
}

Matcher _matchOfInterestSet(List<String> expectedTypes) {
  return predicate(
      (List<Type> x) => unorderedEquals(expectedTypes)
          .matches(x.map((t) => t.type).toList(), {}),
      'interest set $expectedTypes');
}

Matcher _matchPromotionChain(List<String> expectedTypes) {
  if (expectedTypes == null) return isNull;
  return predicate(
      (List<Type> x) =>
          equals(expectedTypes).matches(x.map((t) => t.type).toList(), {}),
      'promotion chain $expectedTypes');
}

Matcher _matchVariableModel(
    {Object chain = anything,
    Object ofInterest = anything,
    Object assigned = anything,
    Object unassigned = anything,
    Object writeCaptured = anything}) {
  Matcher chainMatcher =
      chain is List<String> ? _matchPromotionChain(chain) : wrapMatcher(chain);
  Matcher ofInterestMatcher = ofInterest is List<String>
      ? _matchOfInterestSet(ofInterest)
      : wrapMatcher(ofInterest);
  Matcher assignedMatcher = wrapMatcher(assigned);
  Matcher unassignedMatcher = wrapMatcher(unassigned);
  Matcher writeCapturedMatcher = wrapMatcher(writeCaptured);
  return predicate((VariableModel<Var, Type> model) {
    if (!chainMatcher.matches(model.promotedTypes, {})) return false;
    if (!ofInterestMatcher.matches(model.tested, {})) return false;
    if (!assignedMatcher.matches(model.assigned, {})) return false;
    if (!unassignedMatcher.matches(model.unassigned, {})) return false;
    if (!writeCapturedMatcher.matches(model.writeCaptured, {})) return false;
    return true;
  },
      'VariableModel(chain: ${_describeMatcher(chainMatcher)}, '
      'ofInterest: ${_describeMatcher(ofInterestMatcher)}, '
      'assigned: ${_describeMatcher(assignedMatcher)}, '
      'unassigned: ${_describeMatcher(unassignedMatcher)}, '
      'writeCaptured: ${_describeMatcher(writeCapturedMatcher)})');
}
