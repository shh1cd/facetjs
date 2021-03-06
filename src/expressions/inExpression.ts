module Facet {
  export class InExpression extends BinaryExpression {
    static fromJS(parameters: ExpressionJS): InExpression {
      return new InExpression(BinaryExpression.jsToValue(parameters));
    }

    constructor(parameters: ExpressionValue) {
      super(parameters, dummyObject);
      this._ensureOp("in");
      var lhs = this.lhs;
      var rhs = this.rhs;

      if (!(rhs.canHaveType('SET')
        || (lhs.canHaveType('NUMBER') && rhs.canHaveType('NUMBER_RANGE'))
        || (lhs.canHaveType('TIME') && rhs.canHaveType('TIME_RANGE')))) {
        throw new TypeError(`in expression has a bad type combination ${lhs.type || '?'} in ${rhs.type || '?'}`);
      }

      this.type = 'BOOLEAN';
    }

    public toString(): string {
      return `${this.lhs.toString()} in ${this.rhs.toString()}`;
    }

    protected _getFnHelper(lhsFn: ComputeFn, rhsFn: ComputeFn): ComputeFn {
      var lhsType = this.lhs.type;
      var rhsType = this.rhs.type;
      if ((lhsType === 'NUMBER' && rhsType === 'SET/NUMBER_RANGE') ||
          (lhsType === 'TIME' && rhsType === 'SET/TIME_RANGE')) {
        return (d: Datum) => (<Set>(rhsFn(d))).containsWithin(lhsFn(d));
      } else {
        // Time range and set also have contains
        return (d: Datum) => (<NumberRange>(rhsFn(d))).contains(lhsFn(d));
      }
    }

    protected _getJSExpressionHelper(lhsFnJS: string, rhsFnJS: string): string {
      var lhsType = this.lhs.type;
      var rhsType = this.rhs.type;
      if ((lhsType === 'NUMBER' && rhsType === 'SET/NUMBER_RANGE') ||
        (lhsType === 'TIME' && rhsType === 'SET/TIME_RANGE')) {
        return `${rhsFnJS}.containsWithin(${lhsFnJS})`;
      } else {
        // Time range and set also have contains
        return `${rhsFnJS}.contains(${lhsFnJS})`;
      }
    }

    protected _getSQLHelper(lhsSQL: string, rhsSQL: string, dialect: SQLDialect, minimal: boolean): string {
      var rhs = this.rhs;
      var rhsType = rhs.type;
      switch (rhsType) {
        case 'NUMBER_RANGE':
          if (rhs instanceof LiteralExpression) {
            var numberRange: NumberRange = rhs.value;
            return `(${numberRange.start}<=${lhsSQL} AND ${lhsSQL}<${numberRange.end})`;
          }
          throw new Error('not implemented yet');

        case 'TIME_RANGE':
          if (rhs instanceof LiteralExpression) {
            var timeRange: TimeRange = rhs.value;
            return `('${dateToSQL(timeRange.start)}'<=${lhsSQL} AND ${lhsSQL}<'${dateToSQL(timeRange.end)}')`;
          }
          throw new Error('not implemented yet');

        case 'SET/STRING':
          return `${lhsSQL} in ${rhsSQL}`;

        default:
          throw new Error('not implemented yet');
      }
    }

    public mergeAnd(exp: Expression): Expression {
      if (!this.checkLefthandedness()) return null; //TODO Do something about A is B and C in A
      if (!checkArrayEquality(this.getFreeReferences(), exp.getFreeReferences())) return null;

      if (exp instanceof IsExpression) {
        return exp.mergeAnd(this);
      } else if (exp instanceof InExpression) {
        if (!exp.checkLefthandedness()) return null;
        var rhsType = this.rhs.type;
        if (rhsType !== exp.rhs.type) return Expression.FALSE;
        if (rhsType ===  'TIME_RANGE' || rhsType === 'NUMBER_RANGE' || rhsType.indexOf('SET/') === 0) {
          var intersect = (<LiteralExpression>this.rhs).value.intersect((<LiteralExpression>exp.rhs).value);
          if (intersect === null) return Expression.FALSE;

          return new InExpression({
            op: 'in',
            lhs: this.lhs,
            rhs: new LiteralExpression({
              op: 'literal',
              value: intersect
            })
          }).simplify();
        }
        return null;
      }
      return exp;
    }

    public mergeOr(exp: Expression): Expression {
      if (!this.checkLefthandedness()) return null; //TODO Do something about A is B and C in A
      if (!checkArrayEquality(this.getFreeReferences(), exp.getFreeReferences())) return null;

      if (exp instanceof IsExpression) {
        return exp.mergeOr(this);
      } else if (exp instanceof InExpression) {
        if (!exp.checkLefthandedness()) return null;
        var rhsType = this.rhs.type;
        if (rhsType !== exp.rhs.type) return Expression.FALSE;
        if (rhsType ===  'TIME_RANGE' || rhsType === 'NUMBER_RANGE' || rhsType.indexOf('SET/') === 0) {
          var intersect = (<LiteralExpression>this.rhs).value.union((<LiteralExpression>exp.rhs).value);
          if (intersect === null) return null;

          return new InExpression({
            op: 'in',
            lhs: this.lhs,
            rhs: new LiteralExpression({
              op: 'literal',
              value: intersect
            })
          }).simplify();
        }
        return null;
      }
      return exp;
    }

    protected _specialSimplify(simpleLhs: Expression, simpleRhs: Expression): Expression {
      if (
        simpleLhs instanceof RefExpression &&
        simpleRhs instanceof LiteralExpression &&
        simpleRhs.type.indexOf('SET/') === 0 &&
        simpleRhs.value.empty()
      ) return Expression.FALSE;
      return null;
    }
  }

  Expression.register(InExpression);
}
