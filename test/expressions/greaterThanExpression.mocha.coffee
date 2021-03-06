{ expect } = require("chai")

tests = require './sharedTests'

describe 'GreaterThanExpression', ->
  describe 'with false literal values', ->
    beforeEach ->
      this.expression = { op: 'greaterThan', lhs: { op: 'literal', value: 5 }, rhs: { op: 'literal', value: 5 } }

    tests.complexityIs(3)
    tests.simplifiedExpressionIs({op:'literal', value: false})

  describe 'with true literal values', ->
    beforeEach ->
      this.expression = { op: 'greaterThan', lhs: { op: 'literal', value: 5 }, rhs: { op: 'literal', value: 4 } }

    tests.complexityIs(3)
    tests.simplifiedExpressionIs({op:'literal', value: true})

  describe 'with reference', ->
    beforeEach ->
      this.expression = { op: 'greaterThan', lhs: { op: 'literal', value: 5 }, rhs: { op: 'ref', name: 'flight_time' } }

    tests.complexityIs(3)
    tests.simplifiedExpressionIs({ op: 'lessThan', lhs: { op: 'ref', name: 'flight_time' }, rhs: { op: 'literal', value: 5 } })

  describe 'with complex values', ->
    beforeEach ->
      this.expression = { op: 'greaterThan', lhs: { op: 'literal', value: 7 }, rhs: { op: 'add', operands: [{ op: 'literal', value: 3 }, { op: 'literal', value: 3 }] } }

    tests.complexityIs(5)
    tests.simplifiedExpressionIs({op:'literal', value: true})
