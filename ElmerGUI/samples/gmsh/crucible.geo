cl = 0.002;
fl = 0.02;
Point(1) = {0, -0.06, 0, cl};
Point(2) = {0, -0.04, 0, cl};
Point(3) = {0, -0.03, 0, cl};
Point(4) = {0, -0.02, 0, cl};
Point(5) = {0, 0.03, 0, cl};
Point(6) = {0, 0.04, 0, cl};
Point(7) = {0, 0.06, 0, cl};
Point(8) = {0.05, -0.07, 0, cl};
Point(9) = {0.05, 0.05, 0, cl};
Point(10) = {0.055, 0.05, 0, cl};
Point(11) = {0.055, -0.07, 0, cl};
Point(12) = {0.04, 0.06, 0, cl};
Point(13) = {0.04, -0.06, 0, cl};
Point(14) = {0.025, 0.04, 0, cl};
Point(15) = {0.025, -0.04, 0, cl};
Point(16) = {0.02, -0.03, 0, cl};
Point(17) = {0.02, 0.03, 0, cl};
Point(18) = {0.02, -0.02, 0, cl};
Point(19) = {0, 0.25, 0, fl};
Point(20) = {0, -0.25, 0, fl};
Point(21) = {0.25, 0, 0, fl};
Point(22) = {0, 0, 0, fl};
Line(1) = {7, 6};
Line(2) = {6, 5};
Line(4) = {5, 4};
Line(5) = {4, 3};
Line(6) = {3, 2};
Line(7) = {2, 1};
Line(8) = {1, 13};
Line(9) = {13, 12};
Line(10) = {12, 7};
Line(11) = {2, 15};
Line(12) = {15, 14};
Line(13) = {14, 6};
Line(14) = {5, 17};
Line(15) = {17, 18};
Line(16) = {18, 4};
Line(18) = {18, 16};
Line(19) = {16, 3};
Line(20) = {9, 8};
Line(21) = {8, 11};
Line(22) = {11, 10};
Line(23) = {10, 9};
Circle(24) = {19, 22, 21};
Circle(25) = {21, 22, 20};
Line(26) = {20, 1};
Line(27) = {19, 7};
Line Loop(32) = {9, 10, 1, -13, -12, -11, 7, 8};
Plane Surface(32) = {32};
Line Loop(34) = {11, 12, 13, 2, 14, 15, 18, 19, 6};
Plane Surface(34) = {34};
Line Loop(36) = {19, -5, -16, 18};
Plane Surface(36) = {36};
Line Loop(38) = {4, -16, -15, -14};
Plane Surface(38) = {38};
Line Loop(39) = {20, 21, 22, 23};
Plane Surface(39) = {39};
Line Loop(40) = {25, 26, 8, 9, 10, -27, 24, -23, -22, -21, -20};
Plane Surface(40) = {40};