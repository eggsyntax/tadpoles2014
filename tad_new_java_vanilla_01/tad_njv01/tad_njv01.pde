import processing.video.Capture;

// Currently just trying to get this to work again after some years of neglect.
// Seem to have it to the point now of producing tadpoles and displaying them.

//Change to make -- at least smooth things out a bit by only processing some tads in each frame...
//Optimization -- more sophisticated index into pixels[] in inner loop; replace get() with more efficient code
// specifically: when camera frame is captured, extract brightness into a separate array of floats and use this to
//           compare to each tads brightness

//import processing.opengl.*;

// TODO: maybe only move a random subset of each tadpole on each frame. Maybe have tadpole desire-to-move build up
// randomly over time.

// TODO: tadpoles don't want to be too crowded.

/*

One key question: am I better off figuring out brightness of all points up front, or doing it tadpole by tadpole?
All points:
  Say it's 1000 x 800. That's 800,000
Tadpoles (assumptions: they look 5 pixels away and there are 20,000 tadpoles)
  Num pixels is (5*2+1) * (5*2+1) - 1 = 120.
  120 * 20,000 = 2,400,000

But the numbers change a lot based on width/height and number of tadpoles.

For what number of pixels is the tadpole approach more efficient, assuming the two approaches are equal in cost?
At a constant density of ~.007 tads-per-pixel,
  1600x1600: < 20,000 tads
  1200x1200: < 12,000 tads
   800x800:  <  5,000 tads

Two ways to get substantially greater efficiency:
1) Not all tadpoles move at once. They spend some idle time between moves.
2) Not all pixels are updated for brightnesss every frame.
3) (If I'm using the tadpole-based approach) caching what each tadpole sees might give me some gains. Maybe.
*/

// constants //
final static int NUMTADS = 12000;

final static float VMAX = 500, AMAX = 100;
float VMIN = -1 * VMAX, AMIN = -1 * AMAX; // avoid having to multiply by -1 each time
final static int xRad = 4, yRad = 6; // size of circle

// How far should tadpoles look around them when deciding which way to move?
int vision = 5; // effectively a constant for now but may be implemented
                 // more extensively later. Note that for convenience this
                 // is not a true range but the x & y bounds of a box.
                 
int i,j,ii,jj; // Counters, defining at top level for greatest efficiency

float maxDist;
boolean showCapture = false;
Tad t;
Tad[] tads = new Tad[NUMTADS];
PImage bg;
Capture myCap;
int camFrameRate = 1;
float[] camBri; // brightness values of each pixel of the camera capture
float time,avetime,framecount, lastmillis;

void cameraCheck(String[] cameras) {
  if (cameras.length == 0) {
      println("There are no cameras available for capture.");
      exit();
  } else {
      println("Available cameras:");
      for (int i = 0; i < cameras.length; i++) {
        println(cameras[i]);
      }
  }
}

void cameraSetup() {
  String[] cameras = Capture.list();
  cameraCheck(cameras);
  // The camera can be initialized directly using an 
  // element from the array returned by list().
  // But me, I'm doing it by requesting a specific 
  // width/height/framerate based on what I see in the list.
  myCap = new Capture(this, width, height, camFrameRate);
  myCap.start();     
}

void setup() {
  size(320,256);
  cameraSetup();
  
  int xInitial,yInitial;
  float brightnessInitial;
  
  frameRate(30);
  maxDist = sqrt(width*width + height*height); // What is the farthest one point can be from another?
  
  smooth();
  colorMode(HSB,1.0);
  
  //myCap = new Capture(this,width,height,5);
  //println("myCap: " + myCap);
  camBri = new float[width*height];
  
  noStroke();  ellipseMode(CENTER);
  
  for (i=0;i<NUMTADS;i++) {
    brightnessInitial = random(1.0);
    xInitial = (int)random(width);
    yInitial = (int)random(height);
    tads[i] = new Tad(brightnessInitial,xInitial,yInitial);
  }
  lastmillis=millis();
  
  captureEvent(myCap);
}

void draw() {
  
  background(0,0,.6);
  
  // capture camera
  if (myCap.available()) {
    captureEvent(myCap);
  }
  
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

  // report performance statistics
  framecount++; 
  if (framecount==50) {
    framecount = 0;
    println ("\nave: " + avetime + "; cur: " + time + "; framecount: " + framecount);
  }
}

void captureEvent (Capture myCap) { // Is this actually in use or dead code?
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
  int curPixel;
  Tad (float tadpoleBrightness, int initialX, int initialY) {
    xp = xpDes = initialX; yp = ypDes = initialY;
    xv = yv = xa = ya = age = xvDes = yvDes = 0;
    bri = tadpoleBrightness;
  }
  
    void update() { 
  
      curDif = 1000; xpDes=xp; ypDes=yp; // default value which is sure to be greater than what's found, guaranteeing a chosen destination
    
      // look around for a target pixel
      //println("("+xp+", "+yp+")");
      //println("bg is "+bg);
      curPixel = bg.get((int)xp,(int)yp);
      //println("got here");
      if (abs (bri - brightness(curPixel)) < .1) return; // optional: save some time by skipping ones that are 'good enough'
      
      for (int j = max(0,(int)xp - vision); j < min(width,(int)xp+vision+1 ); j++) {
        for (int k = max(0,(int)yp - vision); k < min(height, (int)yp + vision+1 ); k++) {
    //  for (int j = min(width-1,(int)xp+vision ); j > max(0,(int)xp - vision); j--) {
          //println(camBri[k*width+j]);
          testBri = camBri[k*width+j]; // using camBri rather than bg.get() is much more efficient
          newDif = abs(bri-testBri);
          if (newDif < curDif) {
            curDif = newDif;
            xpDes = j; ypDes = k;
          }
        }
    }
    
    // float distance = abs(xp-xpDes) + abs(yp-ypDes); // not Pythagorean, just a sum -- much faster but less accurate // TODO was not actually being used in prev version
    xa = constrain((xpDes-xp) / maxDist, AMIN, AMAX); ya = constrain ((ypDes-yp) / maxDist, AMIN, AMAX);
    //println("xv: " + xv + "  xa: " + xa);
    xv = constrain(.99 * (xv + xa), VMIN, VMAX);
    yv = constrain(.99 * (yv + ya), VMIN, VMAX);
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
