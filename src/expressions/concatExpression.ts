module Facet {
  export class ConcatExpression extends NaryExpression {
    static fromJS(parameters: ExpressionJS): ConcatExpression {
      return new ConcatExpression(NaryExpression.jsToValue(parameters));
    }

    constructor(parameters: ExpressionValue) {
      super(parameters, dummyObject);
      this._ensureOp("concat");
      this._checkTypeOfOperands('STRING');
      this.type = 'STRING';
    }

    public toString(): string {
      return this.operands.map((operand) => operand.toString()).join(' ++ ');
    }

    protected _getFnHelper(operandFns: ComputeFn[]): ComputeFn {
      return (d: Datum) => {
        return operandFns.map((operandFn) => operandFn(d)).join('');
      }
    }

    protected _getJSExpressionHelper(operandJSExpressions: string[]): string {
      return '(' + operandJSExpressions.join('+') + ')';
    }

    protected _getSQLHelper(operandSQLs: string[], dialect: SQLDialect, minimal: boolean): string {
      return 'CONCAT(' + operandSQLs.join(',')  + ')';
    }

    public simplify(): Expression {
      if (this.simple) return this;
      var simplifiedOperands = this.operands.map((operand) => operand.simplify());
      var hasLiteralOperandsOnly = simplifiedOperands.every((operand) => operand.isOp('literal'));

      if (hasLiteralOperandsOnly) {
        return new LiteralExpression({
          op: 'literal',
          value: this._getFnHelper(simplifiedOperands.map((operand) => operand.getFn()))(null)
        });
      }

      var i = 0;
      while(i < simplifiedOperands.length - 2) {
        if (simplifiedOperands[i].isOp('literal') && simplifiedOperands[i + 1].isOp('literal')) {
          var mergedValue = (<LiteralExpression>simplifiedOperands[i]).value + (<LiteralExpression>simplifiedOperands[i + 1]).value;
          simplifiedOperands.splice(i, 2, new LiteralExpression({
            op: 'literal',
            value: mergedValue
          }));
        } else {
          i++;
        }
      }

      var simpleValue = this.valueOf();
      simpleValue.operands = simplifiedOperands;
      simpleValue.simple = true;
      return new ConcatExpression(simpleValue);
    }
  }
  Expression.register(ConcatExpression);
}
