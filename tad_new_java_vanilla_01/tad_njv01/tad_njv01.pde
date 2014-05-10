import processing.video.Capture;
import java.util.LinkedList;
import java.util.ArrayDeque;

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
    // TODO try commenting out the tadpole drawing, and show the screen cap; see what the cost-per-frame
    // is. At 30k tadpoles, the draw cost for the tads is about 150 ms.
    // Assuming this is pretty quick, I should start looking at a threading solution.
    // Create a queue of captures to process. A thread grabs a cap from the queue, draws it
    // to memory, and adds it to a queue of screens to show. The draw loop just swaps out the
    // screen. This is maybe about the pixels[] array, and loadPixels() and updatePixels().

How to do threading:
    * screen capture writes to an image and adds that image to the capture queue
        if capture.available() {
          capture.read();
          capture_queue.add((PImage)capture); // probably have to copy
        }

    * writeTadpoles() pops from the capture array, uses that info to draw all
    the tadpoles to a PGraphics object, and puts it in the display queue.

    * draw() method pulls from the display queue and draws that PGraphics object to the screen.

    Maybe make a pool of PGraphics objects.

Issue:
    How can a worker know where tadpoles will be when it's time for the screencap they're working on?
    Do I need to pass a copy of all tadpoles to each thread?
    Hmm.
    Maybe I need to make the tadpoles functional/side-effect free? Hmm.

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
final static boolean skipGoodEnough = false;
final static float VMAX = 1500, AMAX = 1100;
float VMIN = -1 * VMAX, AMIN = -1 * AMAX; // avoid having to multiply by -1 each time
final static int xRad = 4, yRad = 6; // size of circle

// How far should tadpoles look around them when deciding which way to move?
int vision = 2; // effectively a constant for now but may be implemented
                 // more extensively later. Note that for convenience this
                 // is not a true range but the x & y bounds of a box.
                 
int i,j,ii,jj; // Counters, defining at top level for greatest efficiency (maybe overkill ;) )

float maxDist;
boolean showCapture = false;
Tad t;
Tad[] tads = new Tad[NUMTADS];
Capture capture; // subclass of PImage
int camFrameRate = 1;
float[] camBri; // brightness values of each pixel of the camera capture
float time,avetime,lastmillis;
int numCores = Runtime.getRuntime().availableProcessors();

// Threading support
int PG_POOL_SIZE = 10;
PgPool pgPool;
LinkedList<Capture> captureQueue = new LinkedList();
LinkedList<PGraphics> displayQueue = new LinkedList();

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
  //cameraCheck(cameras);
  // The camera can be initialized directly using an 
  // element from the array returned by list().
  // But me, I'm doing it by requesting a specific 
  // width/height/framerate based on what I see in the list
  capture = new Capture(this, width, height, camFrameRate);
  capture.start();     
}

class PgPool {
  ArrayDeque<PGraphics> pgPool;

  public PgPool(int size) {
    pgPool = new ArrayDeque(size);
    for (int i=0; i<PG_POOL_SIZE; i++) {
        PGraphics pg = createGraphics(width, height);
        pgPool.push(pg);
    }
  }

  public PGraphics get() {
    return pgPool.pop();
  }

  public void release(PGraphics pg) {
    pgPool.push(pg);
  }
}

class Worker extends Thread {
  /** Looks for a capture, and if one is available, processes it
   *  and adds the resulting screen to the display queue.
   **/

  Worker() {

  }

  // Overriding "start()"
  void start () {}

  // Run method
  void run() {}

}

void setup() {
  size(320, 256, P2D); // P2D?
  cameraSetup();
  
  println("Number of cores: " + numCores);
  int xInitial,yInitial;
  float brightnessInitial;
  
  frameRate(100);
  maxDist = sqrt(width*width + height*height); // What is the farthest one point can be from another?
  pgPool = new PgPool(PG_POOL_SIZE);
  
  smooth();
  colorMode(HSB,1.0);
  
  camBri = new float[width*height];
  
  noStroke();  ellipseMode(CENTER);
  
  for (i=0;i<NUMTADS;i++) {
    brightnessInitial = random(1.0);
    xInitial = (int)random(width);
    yInitial = (int)random(height);
    tads[i] = new Tad(brightnessInitial,xInitial,yInitial);
  }
  lastmillis=millis();
  
  captureEvent(capture);
}

void draw() {
  
  background(0,0,.6);
  
  // capture camera on every 10th frame
  if (frameCount % 10 == 0 && capture.available()) {
    captureEvent(capture);
  }
  
  // update & draw tadpoles
  for(i=0;i<NUMTADS;i++) {
    t = tads[i];
    t.update();
    t.draw();
  }
  
  if (showCapture) {
    // Overlay actual image if mouse clicked
    tint(0,0,1,(float)mouseX/width);    
    image(capture,0,0); // TODO why am I getting a crash on this?
  }

  time = millis() - lastmillis; lastmillis = millis(); avetime = ((avetime*frameCount) + time) / (frameCount+1); 

  // report performance statistics
  if (frameCount%50==0) {
    println ("\nave: " + avetime + " ms; cur: " + time + "; frameCount: " + frameCount);
  }
}

void captureEvent (Capture capture) {
  capture.read();
  for (ii=0;ii<width;ii++) {
   for (jj=0;jj<height;jj++) {
    camBri[jj*width + ii] = brightness(capture.get(ii,jj)); // we put the pixel-by-pixel brightness into a separate array for efficiency.
   }
  }
}

class Point {
    // Holds only state.
    public float x, y;
    public Point(float x, float y) {
        this.x = x;
        this.y = y;
    }
    public Point(int x, int y) {
        this.x = float(x);
        this.y = float(y);
    }
    public Point() {
      // default to 0
      this.x = 0;
      this.y = 0;
    }
}

class Vector extends Point {
    /** Functionally identical to Point, but conceptually
    different. **/
    public Vector(float x, float y) {
        super(x, y);
    }

    public Vector(int x, int y) {
        super(x, y);
    }
    public Vector() {
        // default to 0
        super();
    }
}

class Tad {
    public float bri, age;
    public Point position, destination;
    public Vector velocity, acceleration;
    public color col;
    float testBri,curDif,newDif;
    int curPixel;

    Tad (float tadpoleBrightness, int initialX, int initialY) {
      position = new Point(initialX, initialY);
      velocity = new Vector();
      acceleration = new Vector();
      age = 0;
      bri = tadpoleBrightness;
    }
  
    public Point findDestination(int vision) {
        // look around for a target pixel
        // TODO don't look around again until current destination reached.
        curDif = 5000; // arbitrarily large default
        destination = position; // Default destination = current position
        
        // Don't pick a new destination every frame
        //if (frameCount % 20 == 0) {
        //   return destination;
        //} 
        int x = (int)position.x;
        int y = (int)position.y;

        curPixel = capture.get(x, y); 
        if (skipGoodEnough && abs (bri - brightness(curPixel)) < .1) {
            return destination; // optional: save some time by skipping ones that are 'good enough'
        }
        for (int j = max(0, x - vision); j < min(width, x + vision + 1 ); j++) {
            for (int k = max(0, y - vision); k < min(height, y + vision+1 ); k++) {
                testBri = camBri[k*width+j]; // using camBri rather than capture.get() is much more efficient
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
      
        // Look far around every now and then. Hmm, this'll get overridden when it
        // goes to look around again, though. Unless I've set it up to not look again
        // until current destination is reached.
        /*
        int curVision;
        if (frameCount % 100 == 1) {
          curVision = 200;
        } else {
          curVision = vision;
        }
        */
        // Only makes about 2 ms difference.
        //if (frameCount % 100 == 1) {
            destination = findDestination(vision);
        //}
        age += 1;
    
    // TODO was not actually being used in prev version
    // float distance = abs(xp-xpDes) + abs(yp-ypDes); // not Pythagorean, just a sum -- much faster but less accurate 

    float xa = constrain((destination.x-position.x) / maxDist, AMIN, AMAX);
    float ya = constrain ((destination.y-position.y) / maxDist, AMIN, AMAX);
    float xv = constrain(.99 * (velocity.x + acceleration.x), VMIN, VMAX);
    float yv = constrain(.99 * (velocity.y + acceleration.y), VMIN, VMAX);
    acceleration = new Vector(xa, ya);
    velocity = new Vector(xv, yv);
    //xv = (xpDes-xp) / distance; yv = (ypDes-yp) / distance;
    //xp = constrain(xp += xv,0,width); yp = constrain(yp += yv,0,height);
    position = new Point(position.x + velocity.x, position.y + velocity.y);
    
  }

  void draw() {
    fill(0,0,t.bri,.6);
    Point pos = t.position;
    ellipse(pos.x, pos.y, xRad, yRad);
    //TODO draw tail
  }

}

void mousePressed() {
  showCapture = true;
}

void mouseReleased() {
  showCapture = false;
}
