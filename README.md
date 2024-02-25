# LCW-2

Lazy Cat Works presents.  
PWM(Pulse width modulation) osc module for NTS-1,  
can use as `USER OSCILLATORS`.

# Parameters

- shape (NTS-1: A, other: Shape)  
    PWM depth. (Center is neutral.)  
If shiftshape is 0, this parameter sets pulse width.
- shiftshape (NTS-1: B, other: Shift+Shape)  
Modulation speed.  
If shiftshape is 0, PWM is disabled.
- parameter 1  
Osc type (1..4)<ol type="1">
    <li>Pulse</li>
    <li>Saw</li>
    <li>Tri</li>
    <li>Sin</li></ol>

# How to build
1. Clone (or download) and setup [logue-sdk](https://github.com/korginc/logue-sdk).
1. Clone (or download) this project.
1. Change `PLATFORMDIR` of Makefile according to your environment.

# LICENSE
Copyright 2024 Tomoaki Itoh
This software is released under the MIT License, see LICENSE.txt.

# AUTHOR
Tomoaki Itoh (techno.cat.miau@gmail.com)