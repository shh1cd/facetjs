"use strict";

import BaseModule = require('./base');
import dummyObject = BaseModule.dummyObject;
import Expression = BaseModule.Expression;
import ExpressionJS = BaseModule.ExpressionJS;
import ExpressionValue = BaseModule.ExpressionValue;

export class LiteralExpression extends Expression {
  static fromJS(parameters: ExpressionJS): LiteralExpression {
    return new LiteralExpression(<ExpressionValue>parameters);
  }

  public value: any;

  constructor(parameters: ExpressionValue = {}) {
    super(parameters, dummyObject);
    this.value = parameters.value;
    this._ensureOp("literal");
    if (typeof this.value === 'undefined') {
      throw new TypeError("must have a `value`")
    }
  }

  public valueOf(): ExpressionValue {
    var value = super.valueOf();
    value.value = this.value;
    return value;
  }

  public toJS(): ExpressionJS {
    var js = super.toJS();
    js.value = this.value;
    return js;
  }

  public toString(): string {
    return String(this.value);
  }

  public equals(other: LiteralExpression): boolean {
    return super.equals(other) &&
      this.value === other.value;
  }

  public getFn(): Function {
    var value = this.value;
    return () => value;
  }

  public _getRawFnJS(): string {
    return JSON.stringify(this.value); // ToDo: what to do with higher objects?
  }

  public def(name: string, ex: any) {
    if (!Expression.isExpression(ex)) ex = Expression.fromJS(ex);

  }
}

Expression.classMap["literal"] = LiteralExpression;
