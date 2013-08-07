
class FacetCombine
  constructor: ->
    return

  _ensureMethod: (method) ->
    if not @method
      @method = method # Set the method if it is so far undefined
      return
    if @method isnt method
      throw new TypeError("incorrect combine method '#{@method}' (needs to be: '#{method}')")
    return

  toString: ->
    return @_addName("base combine")

  valueOf: ->
    combine = { method: @method }
    return combine



class SliceCombine extends FacetCombine
  constructor: ({@method, @sort, @limit}) ->
    @_ensureMethod('slice')

  toString: ->
    return "SliceCombine"

  valueOf: ->
    combine = super.valueOf()
    combine.sort = @sort
    combine.limit = @limit
    return combine



class ContinuousCombine extends FacetCombine
  constructor: ({@method}) ->
    @_ensureMethod('matrix')

  toString: ->
    return "MatrixCombine"

  valueOf: ->
    combine = super.valueOf()
    return combine



# Make lookup
combineConstructorMap = {
  "slice": SliceCombine
  "matrix": MatrixCombine
}


FacetCombine.fromSpec = (combineSpec) ->
  CombineConstructor = combineConstructorMap[combineSpec.method or combineSpec.combine]  # ToDo: combineSpec.combine is a backwards compat. hack, remove it.
  throw new Error("unsupported method #{combineSpec.method}") unless CombineConstructor
  return new CombineConstructor(combineSpec)


# Export!
exports.FacetCombine = FacetCombine
exports.SliceCombine = SliceCombine
exports.MatrixCombine = MatrixCombine

