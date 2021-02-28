10 MEMORY &7FFF
20 addr = &8000
30 INPUT "Filename";n$
40 l=LEN(n$)
50 IF l>12 THEN 160
60 POKE addr, l
70 FOR i=1 TO l
80 c$=MID$(n$,i,1)
90 POKE addr+i, ASC(c$)
100 NEXT i
110 PRINT "Copying..."
120 LOAD "COPY.BIN"
130 CALL &8100
140 PRINT "Done."
150 END
160 PRINT "Invalid filename!"
170 GOTO 20