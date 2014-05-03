//Change to make -- at least smooth things out a bit by only processing some tads in each frame...
//Optimization -- more sophisticated index into pixels[] in inner loop; replace get() with more efficient code
// specifically: when camera frame is captured, extract brightness into a separate array of floats and use this to
//           compare to each tads brightness

import processing.video.*;
import processing.opengl.*;


// constants //
final static int NUMTADS = 12000;
final static float VMAX = 200, AMAX = 100;
float VMIN = -1 * VMAX, AMIN = -1 * AMAX; // avoid having to multiply by -1 each time
final static int xRad = 4, yRad = 6; // size of circle

int vision = 5; // effectively a constant for now but may be implemented
                 // more extensively later. Note that for convenience this
                 // is not a true range but the x & y bounds of a box.
int i,j,ii,jj;
float maxDist;
boolean showCapture = false;
Tad t;
Tad[] tads = new Tad[NUMTADS];
PImage bg;
Capture myCap;
float[] camBri; // brightness values of each pixel of the camera capture
float time,avetime,framecount, lastmillis;

void setup() {
  size(320,240,OPENGL);

  int xInitial,yInitial;
  float brightnessInitial;
  
  frameRate(30);
  maxDist = sqrt(width*width + height*height);
  smooth();
  colorMode(HSB,1.0);
  
  myCap = new Capture(this,width,height,5);
  camBri = new float[width*height];
  
  noStroke();  ellipseMode(CENTER);
  
  for (i=0;i<NUMTADS;i++) {
    brightnessInitial = random(1.0);
    xInitial = (int)random(width);
    yInitial = (int)random(height);
    tads[i] = new Tad(brightnessInitial,xInitial,yInitial);
  }
  lastmillis=millis();

  
}

void draw() {
  
  background(0,0,.6);
  
  // update & draw tadpoles
  for(i=0;i<NUMTADS;i++) {
    t = tads[i];
    
    t.update();
    
    fill(0,0,t.bri,.6);
    ellipse(t.xp,t.yp,xRad,yRad);
    
  }
  if (showCapture) {
    tint(0,0,1,(float)mouseX/width);
    image(bg,0,0);
  }

  time = millis() - lastmillis; lastmillis = millis(); avetime = ((avetime*framecount) + time) / (framecount+1); 

  // report statistics
  framecount++; 
  if (framecount==50) {
    framecount = 0;
    println ("\nave: " + avetime + "; cur: " + time + "; framecount: " + framecount);
  }
}

void captureEvent (Capture myCap) {
  myCap.read();
  bg = myCap;
  for (ii=0;ii<width;ii++) {
   for (jj=0;jj<height;jj++) {
    camBri[jj*width + ii] = brightness(bg.get(ii,jj)); // we put the pixel-by-pixel brightness into a separate array for efficiency.
   }
  }
}


class Tad {
  public float xp,yp,xpDes,ypDes,xv,yv,xa,ya,bri,xvDes,yvDes,xaDes,yaDes,age;
  float testBri,curDif,newDif;
  color col;
  int offset;
  Tad (float tadpoleBrightness, int initialX, int initialY) {
    xp = xpDes = initialX; yp = ypDes = initialY;
    xv = yv = xa = ya = age = xvDes = yvDes = 0;
    bri = tadpoleBrightness;
  }
  
  void update() { 

  curDif = 1000; xpDes=xp; ypDes=yp; // default value which is sure to be greater than what's found, guaranteeing a chosen destination

  // look around for a target pixel
  if (abs (bri - brightness (bg.get((int)xp,(int)yp))) < .1) return; // optional: save some time by skipping ones that are 'good enough'
  
  for (int j = max(0,(int)xp - vision); j < min(width,(int)xp+vision+1 ); j++) {
    for (int k = max(0,(int)yp - vision); k < min(height, (int)yp + vision+1 ); k++) {
//  for (int j = min(width-1,(int)xp+vision ); j > max(0,(int)xp - vision); j--) {
      testBri = camBri[k*width+j]; // using camBri rather than bg.get() is much more efficient
      newDif = abs(bri-testBri);
      if (newDif < curDif) {
        curDif = newDif;
        xpDes = j; ypDes = k;
      }
    }
  }
  
  float distance = abs(xp-xpDes) + abs(yp-ypDes); // not Pythagorean, just a sum -- much faster but less accurate
  xa = constrain((xpDes-xp) / maxDist, AMIN, AMAX); ya = constrain ((ypDes-yp) / maxDist, AMIN, AMAX);
  xv = constrain(.99 * (xv + xa), VMIN, VMAX); yv = constrain(.99 * (yv + ya), VMIN, VMAX);
  //xv = (xpDes-xp) / distance; yv = (ypDes-yp) / distance;
  //xp = constrain(xp += xv,0,width); yp = constrain(yp += yv,0,height);
  xp += xv; yp += yv;
  
  }
}

void mousePressed() {
  showCapture = true;
}

void mouseReleased() {
  showCapture = false;
}

