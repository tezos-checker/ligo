// Test a PascaLIGO function with more complex logic than function.ligo

function main (const i : int) : int is
  var j : int := 0 ;
  var k : int := 1 ;
  begin
    j := k + i ;
    k := i + j ;
  end with (k + j)