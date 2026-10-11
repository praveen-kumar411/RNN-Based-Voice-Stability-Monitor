# patch_tb.py : adds a short VCD dump window to tb_top.v (before the last endmodule)
src = open("tb_top.v").read()
block = '''
  // ---- activity dump for power estimation (short window only) ----
  initial begin
    #300000;                          // skip weight loading + back-to-back frames
    $dumpfile("top.vcd");
    $dumpvars(0, tb_top.dut);
    #130000;                          // ~3 frames + idle gaps
    $dumpoff;
  end
'''
if "dumpfile" in src:
    print("Already has a dump block")
else:
    i = src.rfind("endmodule")
    open("tb_top.v", "w").write(src[:i] + block + src[i:])
    print("Patched tb_top.v")
