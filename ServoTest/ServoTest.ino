// Two-servo hardware test for Inventr.io HERO (Arduino Uno compatible).
// Servo power from HERO 5V/GND.
//   D9  = PAN  (confirmed left/right by test)
//   D10 = TILT (confirmed up/down by test)
// Moves one axis at a time with long still gaps between, so any
// unexpected movement on the idle axis is easy to spot.

#include <Servo.h>

const int PAN_PIN = 9;
const int TILT_PIN = 10;
const int CENTER = 90;
const int STEP_DELAY_MS = 40;  // slow, so motion is easy to follow

Servo pan;
Servo tilt;

void sweep(Servo &s, int &angle, const char *name, int target) {
  Serial.print(name);
  Serial.print(" -> ");
  Serial.println(target);

  int step = (target > angle) ? 1 : -1;
  while (angle != target) {
    angle += step;
    s.write(angle);
    delay(STEP_DELAY_MS);
  }
}

void setup() {
  Serial.begin(115200);

  int panAngle = CENTER;
  int tiltAngle = CENTER;

  pan.attach(PAN_PIN);
  tilt.attach(TILT_PIN);
  pan.write(CENTER);
  tilt.write(CENTER);
  Serial.println("Both centered at 90. Holding still 3s.");
  delay(3000);

  Serial.println("=== PAN (D9) MOVING NOW - D10 should be still ===");
  sweep(pan, panAngle, "PAN", 65);
  delay(800);
  sweep(pan, panAngle, "PAN", 115);
  delay(800);
  sweep(pan, panAngle, "PAN", 90);

  Serial.println("=== ALL STILL 5s ===");
  delay(5000);

  // Narrower range on the untested axis: tilt binds sooner and fights gravity.
  Serial.println("=== D10 MOVING NOW - PAN should be still ===");
  sweep(tilt, tiltAngle, "D10", 80);
  delay(800);
  sweep(tilt, tiltAngle, "D10", 100);
  delay(800);
  sweep(tilt, tiltAngle, "D10", 90);

  Serial.println("Test complete. Both centered at 90.");
}

void loop() {
  // Intentionally empty: no repeating sweep.
}
