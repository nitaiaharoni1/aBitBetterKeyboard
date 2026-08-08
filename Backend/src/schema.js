// Turns the client's plain field list (`CloudField` in
// `Packages/AIKeyboardCore/Sources/AIKeyboardShared/CloudTransport.swift`) into
// the OpenAPI-shaped schema Vertex's `responseSchema` expects: uppercase type
// names, and `nullable: true` because a field the model has nothing to fill —
// Reply's addressee when the message names no one, the screen reader's sender
// when nothing is worth replying to — needs to be able to say so rather than
// invent a value to satisfy the type.
//
// A field carrying `items` becomes an ARRAY of OBJECT instead of a flattened
// string, because that is the shape the client sends. Do not defend it with a
// number: `Bar/screen-context/ablation/flatten.json` re-measured the flattened
// version against the nested one in a single sitting and found nested a point
// *worse* on sender, inside the noise. The claim that flattening cost 7 points
// was in `CloudField.items`'s doc comment and did not survive. What *is*
// load-bearing is that the list exists at all — dropping the enumeration costs
// 2 points of sender, 3 of keyboard language, and lets a trap through.
//
// Recursive because `items` fields can themselves nest, even though today only
// the screen reader's `messages` field does.

function propertySchema(field) {
  if (field.items && field.items.length > 0) {
    return {
      type: "ARRAY",
      description: field.description,
      nullable: true,
      items: objectSchema(field.items)
    };
  }
  return { type: "STRING", description: field.description, nullable: true };
}

function objectSchema(fields) {
  const properties = {};
  for (const field of fields) properties[field.name] = propertySchema(field);
  return {
    type: "OBJECT",
    properties,
    // `propertyOrdering` is what makes field order load-bearing end to end:
    // the model fills fields in this order, so a field the prompt needs
    // decided first (Reply's `unnamed`, Rewrite's `decision`) only works if it
    // is listed first here, in the same order the client sent it — never
    // re-sorted, e.g. alphabetically, on the way through.
    required: fields.map((field) => field.name),
    propertyOrdering: fields.map((field) => field.name)
  };
}

export function buildResponseSchema(fields) {
  return objectSchema(fields);
}
