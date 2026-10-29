SetMemoryMax(768)
pass = Select(AMT_PASS, 1, 2, 3)
AMT_PRE_PROC = AMT_PASS < 2
AMT_SOURCE.KFMDeint(mode=4, pass=pass, preset="Ultra Fast", threads=2, ucf=false, nr=false, svp=false, thswitch=3, cuda=false, is120=false, filepath=AMT_TMP)
AssumeBFF()
