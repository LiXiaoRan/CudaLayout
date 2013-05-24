from __future__ import print_function
import sys

def circle(nnodes):
    for i in range(nnodes):
        print('  <node id="n{0}" />'.format(i))
        print('  <edge id="e{0}" source="n{0}" target="n{1}" />'.format(
            i, (i+1)%nnodes))
def k(n):
    for i in range(n):
        print('  <node id="n{0}" />'.format(i))
        for j in range(i+1,n):
            print('  <edge id="e{0}-{1}" source="n{0}" target="n{1}" />'.format(
                i, j))
def grid(n):
    for i in range(n):
	for j in range(n):
  	    print('	<node id="n{0}n{1}" />'.format(i,j))
#	    if i > 0:
#		print('	<edge id="e{0}n{1}--{2}n{1}" source="n{0}n{1}" target="n{2}n{1}" />'.format(i,j,i-1))
	    if i < n-1:
		print('	<edge id="e{0}n{1}--{2}n{1}" source="n{0}n{1}" target="n{2}n{1}" />'.format(i,j,i+1))
#	    if j > 0:
#		print('	<edge id="e{0}n{1}--{0}n{2}" source="n{0}n{1}" target="n{0}n{2}" />'.format(i,j,j-1))
	    if j < n-1:
		print('	<edge id="e{0}n{1}--{0}n{2}" source="n{0}n{1}" target="n{0}n{2}" />'.format(i,j,j+1))


nnodes = 5
if len(sys.argv) > 1:
    nnodes = int(sys.argv[2])
    if sys.argv[1] == '-c':
        gen = circle
    elif sys.argv[1] == '-k':
        gen = k
    elif sys.argv[1] == '-g':
	gen = grid

print('<?xml version="1.0"?>')
print('<graphml>')
print(' <graph id="g">')
gen(nnodes)
print(' </graph>')
print('</graphml>')
