module {
  func.func @type_conversion(%arg0: i32) -> f32 {
    %converted = builtin.unrealized_conversion_cast %arg0 : i32 to f32
    return %converted : f32
  }
}
