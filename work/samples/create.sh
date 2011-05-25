#!/bin/sh

#for i in 'fake.test.show.s01e01.foobar.avi' 'Psych [4x14] Think Tank.avi' 'Seinfeld [4x03.4x04].avi'
for i in 'chase 2010 [1x5] foobar.avi' 'chase 2010 [1x1] ass.avi'
do
  ls / > "$i"
done
