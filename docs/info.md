## How it works

A case statement turns the four input bits into the pattern of segments to light, where a 1 lights a segment. There is no clock, so the display changes as soon as the input does.

## How to test

Set ui[3:0] to a number from 0 to 15. Numbers 0 to 9 show as digits, and 10 to 15 show as A, b, C, d, E and F.

## External hardware

A common-cathode seven-segment display on uo[0] to uo[6], with a resistor on each segment.
