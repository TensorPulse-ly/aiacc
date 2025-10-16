module {
  simple.hello
  
  simple.print "Hello World"
  simple.print "Testing extended features!"
  simple.print "Attributes work correctly"
  
  func.func @test_math() -> i32 {
    %0 = arith.constant 10 : i32
    %1 = arith.constant 20 : i32
    
    %2 = simple.add %0, %1 : i32
    
    return %2 : i32
  }
}