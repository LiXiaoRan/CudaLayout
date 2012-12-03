#include <stdio.h>
#include <stdlib.h>

#include "layout.h"

__global__ void layout(node* nodes, unsigned char* edges, int numNodes, int width, int height, int iterations, float ke, float kh, float mass, float time, float coefficientOfRestitution, int forcemode){
  int me = blockIdx.x * 8 + threadIdx.x;
  
  if(me >= numNodes){
    return;
  }
  float fx, fy;
  for(int z=0;z<iterations;z++){
    fx = fy = 0;
    for(int i =0; i < numNodes; i++){
      if( i == me){
	continue;
      }

      //Distance between two nodes
      float dx = nodes[me].x - nodes[i].x;
      float dy = nodes[me].y - nodes[i].y;
      float dist = sqrtf(dx*dx + dy *dy);

      //Work out the repulsive coulombs law force      
      if((forcemode & COULOMBS_LAW) != 0){
	float q1 = 3, q2 = 3;
	
	if(dist < 1 || !isfinite(dist)){
	  dist = 1;
	}
	float f = ke*q1*q2/ (dist*dist * dist);
	if(isfinite(f)){
	  fx += dx * f;
	fy += dy * f;
	}
      }
      if((forcemode & HOOKES_LAW_SPRING) != 0 && edges[i + me * numNodes]){
	//Attractive spring force
	//float naturalDistance = nodes[i].width + nodes[me].height; //TODO different sizes
	float naturalWidth = nodes[i].width + nodes[me].width;
	float naturalHeight = nodes[i].height + nodes[me].height;
	fx += -kh * (abs(dx) - naturalWidth) * dx/dist;
	fy += -kh * (abs(dy) - naturalHeight)* dy/dist;      
      }
    }

    //Friction against ground
    float g = 9.8f;
    float Muk = 0.04; //Kinetic Friction Coefficient
    float Mus = 0.2; //Static Friction Coefficient
    float speed = nodes[me].dx * nodes[me].dx + nodes[me].dy * nodes[me].dy;
    speed = sqrt(speed);
    float normx = nodes[me].dx / speed;
    float normy = nodes[me].dy / speed;
    
    if((forcemode & FRICTION) != 0){
      if(nodes[me].dx == 0 && nodes[me].dy ==0 ){
	//I am stationary
	float fFric = Mus * mass * g;
	if(abs(fFric* normx) >= abs(fx)  && abs(fFric*normx) >= abs(fy)){
	  fx = fy = 0;
      }else{
	  //Just ignore friction this tick -- only really happens once
	}
      }else{
	float fFric = Muk * mass * g;
	fx += -copysign(fFric*normx, nodes[me].dx);
	fy += -copysign(fFric*normy, nodes[me].dy);
      }
    }
    
    //Drag
    if((forcemode & DRAG)!= 0 &&  speed != 0){
      float crossSec = nodes[me].width / 1000.0f;
      float fDrag = 0.25f * crossSec * speed * speed;
      float fdx = -copysign(fDrag * normx, nodes[me].dx);
      float fdy = -copysign(fDrag * normy, nodes[me].dy);
      
      fx += fdx;
      fy += fdy;
    }

    //Move
    //F=ma => a = F/m
    float ax = fx / mass;
    float ay = fy / mass;


    if(ax > width/3){
      ax = width/3;
    }else if(ax < -width/3){
      ax = -width/3;
    }else if(!isfinite(ax)){
      ax = 0;
    }
    
    if(ay > height/3){
      ay = height/3;
    }else if(ay < -height/3){
      ay = -height/3;
    }else if(!isfinite(ay)){
      ay = 0;
    }
    
    nodes[me].nextX = nodes[me].x + nodes[me].dx*time;
    nodes[me].nextY = nodes[me].y + nodes[me].dy*time;
    nodes[me].nextdy =nodes[me].dy + ay*time;
    nodes[me].nextdx =nodes[me].dx + ax*time;
    
    //Make sure it won't be travelling too fast
    if(nodes[me].nextdx * time > width/2){
      nodes[me].nextdx = width/(2*time);
    }else if(nodes[me].nextdx * time < -width/2){
      nodes[me].nextdx = -width/(2*time);
    }
    
    if(nodes[me].nextdy * time > height / 2){
      nodes[me].nextdy = height/(2*time);
    }else if(nodes[me].nextdy * time < -height/2){
      nodes[me].nextdy = -height/(2*time);
    }
    
    //But wait - There are bounds to check!
    float collided = coefficientOfRestitution; //coeeficient of restitution
    if(nodes[me].nextX + nodes[me].width/2 > width){
      nodes[me].nextX = 2* width - nodes[me].nextX - nodes[me].width;
      nodes[me].nextdx *= collided;
    }else if(nodes[me].nextX < nodes[me].width/2){
      nodes[me].nextX =  nodes[me].width - nodes[me].nextX;
      nodes[me].nextdx *= collided;
    }
    
    if(nodes[me].nextY + nodes[me].height/2 > height){
	nodes[me].nextY = 2*height - nodes[me].nextY - nodes[me].height;
	nodes[me].nextdy *= collided;
    }else if(nodes[me].nextY < nodes[me].height/2){
      nodes[me].nextY = nodes[me].height - nodes[me].nextY; 
      nodes[me].nextdy *= collided;
    }
    
    //Update
    nodes[me].x = nodes[me].nextX;
    nodes[me].y = nodes[me].nextY;
    nodes[me].dx = nodes[me].nextdx;
    nodes[me].dy = nodes[me].nextdy;
  }
}


void graph_layout(graph* g, int width, int height, int iterations, float ke, float kh, float mass, float time, float coefficientOfRestitution, int forcemode){
  /*
    need to allocate memory for nodes and edges on the device
  */
  unsigned char* edges_device;
  node* nodes_device;
  cudaError_t err;

  err = cudaMalloc(&edges_device, sizeof(unsigned char)* g->numNodes* g->numNodes);
  if(err != cudaSuccess){
    printf("Memory allocation for edges failed\n");
    return;
  }
  
  err = cudaMalloc(&nodes_device, sizeof(node) * g->numNodes);
  if(err != cudaSuccess){
    printf("Memory allocation for nodes failed\n");
    return;
  }
  
  /* copy data to device */
  err = cudaMemcpy(edges_device, g->edges, sizeof(unsigned char)* g->numNodes* g->numNodes, cudaMemcpyHostToDevice);
  if(err != cudaSuccess){
    printf("Error return from cudaMemcpy edges to device\n");
  }

  err = cudaMemcpy(nodes_device, g->nodes, sizeof(node)* g->numNodes, cudaMemcpyHostToDevice);
  if(err != cudaSuccess){
    printf("Error return from cudaMemcpy nodes to device\n");
  }

  
  /*COMPUTE*/
  int nth = 8;
  int nbl = ceil(g->numNodes / 8.0);
  //printf("Graph has %d nodes with %d blocks and %d threads\n", g->numNodes, nbl, nth);
  layout<<<nbl,nth>>>(nodes_device, edges_device, g->numNodes,width,height, iterations,ke, kh, mass, time, coefficientOfRestitution, forcemode);
  
  /*After computation you must copy the results back*/
  err = cudaMemcpy(g->nodes, nodes_device, sizeof(node)* g->numNodes, cudaMemcpyDeviceToHost);
  if(err != cudaSuccess){
    printf("Error return from cudaMemcpy nodes to device\n");
  }
  
  
  
  /*
    All finished, free the memory now
  */
  err = cudaFree(nodes_device);
  if(err != cudaSuccess){
    printf("Freeing nodes failed\n");
  }
  
  err = cudaFree(edges_device);
  if(err != cudaSuccess){
    printf("Freeing edges failed\n");
  }
  
}

