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

// TODO: the first portrait works great, because there are tadpoles everywhere. But once, say, all the white
// ones have gone to the far left, they don't see if things change on the right. The first solution that occurs
// to me is to have each tadpole occasionally look far away.
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

Note: tried cutting down the frame cap rate (calls to captureEvent()) by as much as a factor of 50;
    it made almost no difference to average time per frame.
So we could do the tadpole approach but cache results. But since cutting down capture rate doesn't gain
    us much of anything, it's probably not worth bothering.

How can I get greatest efficiency in reading from the camera? What exactly is a Capture anyway?

Some ways to get substantially greater efficiency:
1) Not all tadpoles move at once. They spend some idle time between moves. If I do this, I can let the individual
    tadpoles move faster.
2) Not all pixels are updated for brightnesss every frame.
3) (If I'm using the tadpole-based approach) caching what each tadpole sees might give me some gains. Maybe.
4) Not every tadpole looks for a new spot every time. When they find one, they set a destination, but that destination
    isn't always updated.

Efficient way to use random numbers to choose a limited # of tadpoles to move:
    Give the tadpoles a threshold for moving; aka their desire to move builds up gradually over time.
    Cycle through a list of random numbers on each frame and add a random amount to each tadpole's desire.
    Maybe make the list length be num_tadpoles + 1

Note to self: can run from vim using: :!make > /dev/null 2>&1 &
Or in my case just: ':make &'. See https://stackoverflow.com/questions/666453/running-make-from-gvim-in-background
*/

// constants //
final static int NUMTADS = 10000;

final static float VMAX = 1500, AMAX = 1100;
float VMIN = -1 * VMAX, AMIN = -1 * AMAX; // avoid having to multiply by -1 each time
final static int xRad = 4, yRad = 6; // size of circle

// How far should tadpoles look around them when deciding which way to move?
int vision = 5; // effectively a constant for now but may be implemented
                 // more extensively later. Note that for convenience this
                 // is not a true range but the x & y bounds of a box.
                 
int i,j,ii,jj; // Counters, defining at top level for greatest efficiency (maybe overkill ;) )

float maxDist;
boolean showCapture = false;
Tad t;
Tad[] tads = new Tad[NUMTADS];
PImage bg;
Capture myCap;
int camFrameRate = 1;
float[] camBri; // brightness values of each pixel of the camera capture
float time,avetime,lastmillis;
int numCores = Runtime.getRuntime().availableProcessors();


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
  // width/height/framerate based on what I see in the list
  // prov
  myCap = new Capture(this, width, height, camFrameRate);
  myCap.start();     
}

void setup() {
  size(320, 256, P2D);
  cameraSetup();
  
  println("Number of cores: " + numCores);
  int xInitial,yInitial;
  float brightnessInitial;
  
  frameRate(80);
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
  
  // capture camera on every 10th frame
  if (frameCount % 10 == 0 && myCap.available()) {
    captureEvent(myCap);
  }
  
  // update & draw tadpoles
  for(i=0;i<NUMTADS;i++) {
    t = tads[i];
    
    t.update();
    
    fill(0,0,t.bri,.6);
    Point pos = t.position;
    ellipse(pos.x, pos.y, xRad, yRad);
    
  }
  if (showCapture) {
    tint(0,0,1,(float)mouseX/width);
    image(bg,0,0);
  }

  time = millis() - lastmillis; lastmillis = millis(); avetime = ((avetime*frameCount) + time) / (frameCount+1); 

  // report performance statistics
  // frameCount++; 
  if (frameCount%50==0) {
  //   frameCount = 0;
    println ("\nave: " + avetime + " ms; cur: " + time + "; frameCount: " + frameCount);
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

class Point {
    public final float x, y;
    public Point(float x, float y) {
        this.x = x;
        this.y = y;
    }
    public Point(int x, int y) {
        this.x = float(x);
        this.y = float(y);
    }
    
}

class Tad {
    public float xv,yv,xa,ya,bri,xvDes,yvDes,xaDes,yaDes,age;
    float testBri,curDif,newDif;
    Point position, destination;
    color col;
    int offset;
    int curPixel;
    Tad (float tadpoleBrightness, int initialX, int initialY) {
      position = new Point(initialX, initialY);
      xv = yv = xa = ya = age = xvDes = yvDes = 0;
      bri = tadpoleBrightness;
    }
  
    public Point findDestination() { 
        // look around for a target pixel
    
        curDif = 5000; // arbitrarily large default
        destination = position; // Default destination = current position
        int x = (int)position.x;
        int y = (int)position.y;

        curPixel = bg.get(x, y); 
        if (abs (bri - brightness(curPixel)) < .1) return destination; // optional: save some time by skipping ones that are 'good enough'
        for (int j = max(0, x - vision); j < min(width, x + vision + 1 ); j++) {
            for (int k = max(0, y - vision); k < min(height, y + vision+1 ); k++) {
                testBri = camBri[k*width+j]; // using camBri rather than bg.get() is much more efficient
                newDif = abs(bri-testBri);
                if (newDif < curDif) {
                    curDif = newDif;
                    destination = new Point(j, k);
                }
            }
        }
        return destination;
    }

    void update() {
        if (frameCount % 10 == 1) {
            destination = findDestination();
        }
        age += 1;
    
    // float distance = abs(xp-xpDes) + abs(yp-ypDes); // not Pythagorean, just a sum -- much faster but less accurate // TODO was not actually being used in prev version
    xa = constrain((destination.x-position.x) / maxDist, AMIN, AMAX);
    ya = constrain ((destination.y-position.y) / maxDist, AMIN, AMAX);
    //println("xv: " + xv + "  xa: " + xa);
    xv = constrain(.99 * (xv + xa), VMIN, VMAX);
    yv = constrain(.99 * (yv + ya), VMIN, VMAX);
    //xv = (xpDes-xp) / distance; yv = (ypDes-yp) / distance;
    //xp = constrain(xp += xv,0,width); yp = constrain(yp += yv,0,height);
    position = new Point(position.x + xv, position.y + yv);
    
  }
}

void mousePressed() {
  showCapture = true;
}

void mouseReleased() {
  showCapture = false;
}
