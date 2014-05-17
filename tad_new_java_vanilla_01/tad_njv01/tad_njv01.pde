import processing.video.Capture;
import java.util.concurrent.LinkedBlockingDeque;
import processing.core.PGraphics;
import java.util.concurrent.PriorityBlockingQueue;

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
    Yes. Tadpoles are immutable. update() returns a new tadpole. The current list of tadpoles is stored in 
    a queue, and worker threads pull from that queue to draw them, returning a PGraphics object. Meanwhile
    the "current" list becomes the list of new tadpoles. Costs memory (10,000 tadpoles for each frame
    sitting in the queue and waiting to be drawn).

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
final static boolean skipGoodEnough = true;
final static float VMAX = 1500, AMAX = 1100;
float VMIN = -1 * VMAX, AMIN = -1 * AMAX; // avoid having to multiply by -1 each time
final static int xRad = 4, yRad = 6; // size of circle

// How far should tadpoles look around them when deciding which way to move?
int vision = 5; // effectively a constant for now but may be implemented
                 // more extensively later. Note that for convenience this
                 // is not a true range but the x & y bounds of a box.
                 
float maxDist;
boolean showCapture = false;
Tad t;
Capture capture; // subclass of PImage
int camFrameRate = 1;
float[] camBri; // brightness values of each pixel of the camera capture
float time,avetime,lastmillis;
int numCores = Runtime.getRuntime().availableProcessors();

// Threading support
final int PG_POOL_SIZE = 10;
final int IMAGE_POOL_SIZE = 10;
PgPool pgPool;
PriorityBlockingQueue<TadpoleState> tadpoleStateQueue = new PriorityBlockingQueue();
PriorityBlockingQueue<PGraphicsWithTimestamp> displayQueue = new PriorityBlockingQueue();

// Two temporary deques and an int to track timestamps
//LinkedBlockingDeque<Integer> tadpoleStateTimestampQueue = new LinkedBlockingDeque();
//LinkedBlockingDeque<Integer> displayTimestampQueue = new LinkedBlockingDeque();
//LinkedBlockingDeque<Integer> tadpoleStateCaptureTimestampQueue = new LinkedBlockingDeque();
//LinkedBlockingDeque<Integer> displayCaptureTimestampQueue = new LinkedBlockingDeque();
//int lastTimestamp;

//boolean updateLocked = false;
//boolean drawLocked = false;

class TadpoleState implements Comparable<TadpoleState> {
  /** contains an array of tadpoles along with a timestamp (for prioritization) **/
  public Tad[] tads;
  public int timestamp;
  public boolean alreadyUpdated = false;
  public boolean locked = false;

  public TadpoleState(Tad[] tads, int timestamp) {
    this.tads = tads;
    this.timestamp = timestamp;
  }

  public TadpoleState lock() {
    if (locked) return null; // Already locked, forget about it.
    locked = true;
    return this; // for convenience
  }

  @Override
  public int compareTo(TadpoleState other) {
    // Compare based on timestamp. Reversed from what would be intuitive because
    // the head of PriorityQueue is the *smallest* item.
    if (this.timestamp < other.timestamp) return 1;
    if (this.timestamp > other.timestamp) return -1;
    return 0;
  }
}

class PGraphicsWithTimestamp implements Comparable<PGraphicsWithTimestamp> {
  public PGraphics pg;
  public int timestamp;

  public PGraphicsWithTimestamp(PGraphics pg, int timestamp) {
    this.pg = pg;
    this.timestamp = timestamp;
  }

  @Override
  public int compareTo(PGraphicsWithTimestamp other) {
    // Compare based on timestamp. Reversed from what would be intuitive because
    // the head of PriorityQueue is the *smallest* item.
    if (this.timestamp < other.timestamp) return 1;
    if (this.timestamp > other.timestamp) return -1;
    return 0;
  }
} 
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
  /** Pool of PGraphics objects **/
  LinkedBlockingDeque<PGraphics> pgPool;

  public PgPool(int size) {
    pgPool = new LinkedBlockingDeque(size);
    for (int i=0; i<PG_POOL_SIZE; i++) {
        PGraphics pg = createGraphics(width, height);
        pg.beginDraw();
        pg.smooth();
        pg.colorMode(HSB,1.0);
        pg.noStroke();
        pg.ellipseMode(CENTER);
        pg.endDraw();
        _put(pg);
    }
  }

  void _put(PGraphics p) {
    // Internal method for putting
    try {
      pgPool.putLast(p);
    }
    catch (InterruptedException e) {
      println("pgPool putting interrupted, argh!");
    }
  }
  public PGraphics get() {
    return pgPool.pollFirst();
  }

  public void release(PGraphics pg) {
    _put(pg);
  }
}

class Worker extends Thread {
  /** Looks for something to do and does it. Either processes a
   *  capture and puts it in the capture queue or pulls a capture
   *  out of the queue and draws an image.
   *
   *  1. If there's a capture available, read it and update the
   *    camBri array.
   *  2. If the tadpole-state queue is short, grab the first member
   *    of it and update all the tadpoles using the camBri array,
   *    appending the result to the tadpole-state queue.
   *  3. If the PGraphics queue is short, pop the first member of the
   *    tadpole-state queue and use it to draw to a PGraphics object
   *    from the pool, appending the result to the PGraphics queue.
   *  4. Otherwise take a nice nap.
   *
   **/

  Worker() {

  }

  // Overriding "start()"
  void start () {
    super.start();
  }

  // Run method
  // TODO The problem at this point: threads take a variable time to complete, so 
  // the display screens (maybe the tadpole states also) are being put in the queue
  // out of order (by, eg, 65 ms). What to do about this? Maybe look at LinkedList options so they
  // can more easily swap elements? Or some kind of map? But keying by millis()
  // won't work well because only a small percentage of them will appear. Hmm.
  // I could actually probably append them the minute I get them, since they're mutable. Although
  // not guaranteed, and (maybe?) doesn't solve the problem
  // TODO next: try this last approach!
  void run() {
    while (true) {
      // Perform triage on what needs doing
      if (capture.available()) {
        //println("Let's capture!");
        captureEvent(capture);
      }

      if (displayQueue.size() > 4) {
        // Display queue is getting a bit behind; do an extra draw cycle
        drawScreen();
        return;
      }

      // TODO NOT WORKING! Because the peeking isn't thread-safe? Can't guarantee that between the
      // time we peek and the time we evaluate, something hasn't happened. We end up with a spuriously
      // locked state pretty early. Not *exactly* sure what's happening. Or we end up with an empty
      // state queue. Do we ever go further if there's an empty state queue?
      // Think about either a) how to do this atomically, or b) some other solution.

      // We always base the next tadpole state on the most current one we have
      
      TadpoleState latestTadpoles = tadpoleStateQueue.peek().lock();
      if (latestTadpoles == null) return;
      /*
      print("Conditions: null? " + (latestTadpoles==null));
      print("; size? " + tadpoleStateQueue.size());
      print("; alreadyUp? " + latestTadpoles.alreadyUpdated);
      println("; tads null? " + (latestTadpoles.tads==null));
      */

      if (tadpoleStateQueue.size() < 5 && latestTadpoles.tads != null && (!latestTadpoles.alreadyUpdated || tadpoleStateQueue.size()==1)) { // awkward as fuck to have the null check AND the locked check AND the alreadyUpdated check...
          //println("Let's update!");
          latestTadpoles.alreadyUpdated = true;
          Tad[] newtads = updateTadpoles(latestTadpoles.tads);
          tadpoleStateQueue.add(new TadpoleState(newtads, millis()));
          //println("We updated!");
          latestTadpoles.locked = false;

      } else if (tadpoleStateQueue.size() > 1) { // So we don't run out of tadpoles to peek at
        latestTadpoles.locked = false;
        //println("let's draw!");
        TadpoleState state = tadpoleStateQueue.poll();

        if (state != null) { // TODO still needed?
          drawTadpoles(state);
        }
      }
      else {
        latestTadpoles.locked = false;
        println("Sleeping. tadpole/draw queues: " + tadpoleStateQueue.size() + ", " + displayQueue.size());
        try {
          sleep(100); // in ms
        }
        catch (InterruptedException e) {
          println("You interrupted my damn nap.");
          exit();
        }
      }
    }
  }
  // TODO possibly implement quit() method
}

void setup() {
  size(320, 256, P2D); // P2D?
  cameraSetup();
  
  println("Number of cores: " + numCores);
  int xInitial,yInitial;
  float brightnessInitial;
  
  frameRate(30); // TODO put back up high?
  maxDist = sqrt(width*width + height*height); // What is the farthest one point can be from another?
  pgPool = new PgPool(PG_POOL_SIZE);
  
  smooth();
  colorMode(HSB,1.0);
  //println("Base colorMode: " + self.colorMode);
  camBri = new float[width*height];
  
  noStroke();
  ellipseMode(CENTER);
  
  Tad[] tads = new Tad[NUMTADS];
  for (int i=0;i<NUMTADS;i++) {
    brightnessInitial = random(1.0);
    xInitial = (int)random(width);
    yInitial = (int)random(height);
    tads[i] = new Tad(brightnessInitial, new Point(xInitial,yInitial));
  }
  // push our newborn tadpoles into the tadpoleStateQueue
  tadpoleStateQueue.add(new TadpoleState(tads, millis()));

  lastmillis=millis();
  
  captureEvent(capture);

  // And finally, create some Workers to do all the work
  Worker[] workers = new Worker[numCores-1];
  for (int i=0; i<(numCores-1); i++) {
    Worker worker = new Worker();
    worker.start();
    workers[i] = worker;
  }
}

Tad[] updateTadpoles(Tad[] currentTadpoles) {
  //println("Update based on Tad[] " + currentTadpoles);
  //println("updating. stateQueue length: " + tadpoleStateQueue.size());
  Tad[] newtads = new Tad[NUMTADS]; // Temporary storage for updated tadpoles

  // We always base the next tadpole state on the most current one we have

  for(int i=0;i<NUMTADS;i++) {
    t = currentTadpoles[i];
    Tad newtad = t.update();
    newtads[i] = newtad;
  }

  return newtads;
}

void drawTadpoles(TadpoleState state) {
  PGraphics nextScreen = pgPool.get();
  Tad[] tadpoles = state.tads;
  int timestamp = state.timestamp;
  nextScreen.beginDraw();
  nextScreen.background(0, 0, 0.7); // Delete leftover tadpoles from last time it was used
  for(int i=0;i<NUMTADS;i++) {
    t = tadpoles[i];
    t.draw(nextScreen);
  }
  nextScreen.endDraw();

  displayQueue.put(new PGraphicsWithTimestamp(nextScreen, timestamp));
}

void draw() {
  drawScreen();
}

void drawScreen() {
  
  if (displayQueue.size() == 0) return; //TODO should be able to delete this now that I'm using thread-safe queues
  PGraphicsWithTimestamp nextScreen = null;
  try {
    nextScreen = displayQueue.take();
  }
  catch (InterruptedException e) {
    println("pgPool putting interrupted, argh!");
  }
  if (nextScreen != null) {
    image(nextScreen.pg, 0, 0);
    pgPool.release(nextScreen.pg); // TODO should this release actually be happening in drawScreen? Probably.
    int timeDiff = millis() - nextScreen.timestamp;
    //println("Displaying capture taken " + timeDiff + " milliseconds ago.");
    //lastTimestamp = timestamp;
  }

  if (showCapture) {
    // Overlay actual image if mouse clicked
    tint(0,0,1,(float)mouseX/width);    
    image(capture,0,0); // TODO why am I getting a crash on this?
  }


  time = millis() - lastmillis; lastmillis = millis(); avetime = ((avetime*frameCount) + time) / (frameCount+1); 

  // report performance statistics
  if (frameCount%10==0) {
    println("stateQueue: " + tadpoleStateQueue.size() + "; displayQueue: " + displayQueue.size());
  }
  if (frameCount%50==0) {
    println("\nave: " + avetime + " ms; cur: " + time + "; frameCount: " + frameCount);
  }
}

void captureEvent (Capture capture) {
  if (!capture.available()) return;
  capture.read();
  for (int ii=0;ii<width;ii++) {
   for (int jj=0;jj<height;jj++) {
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
    public float bri;
    public int age;
    public Point position, destination;
    public Vector velocity, acceleration;
    float testBri,curDif,newDif;

    Tad(float tadpoleBrightness, Point position) {
      this(tadpoleBrightness, position, new Vector(), new Vector(), 0);
    }
  
    Tad(float tadpoleBrightness, Point position, Vector velocity, Vector acceleration, int age) {
      this.position = position;
      this.velocity = velocity;
      this.acceleration = acceleration;
      this.age = age;
      this.bri = tadpoleBrightness;
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
        //println("x, y:" + x + ", " + y);

        float curBri = brightness(capture.get(x, y)); //TODO shouldn't this be camBri?!?!?! As below...
        //float curBri = camBri[y*width+x];
        if (skipGoodEnough && abs (bri - curBri) < .1) {
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

    Tad update() {
      
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
    
    return new Tad(bri, position, velocity, acceleration, age + 1);
  }

  void draw(PGraphics pg) {
    // Note that beginDraw() and endDraw() happen outside this function
    //pg.colorMode(HSB, 1.0);
    pg.fill(0,0,t.bri,.6);
    Point pos = t.position;
    pg.ellipse(pos.x, pos.y, xRad, yRad);
    //TODO draw tail
  }

}

void mousePressed() {
  showCapture = true;
}

void mouseReleased() {
  showCapture = false;
}
