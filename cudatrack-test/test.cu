
#include "cuda_runtime.h"
#include "device_launch_parameters.h"

#include "std_incl.h"
#include "utils.h"

#include <cassert>
#include <cstdlib>
#include <stdio.h>
#include <windows.h>
#include <cstdarg>
#include <valarray>

#include "cudafft/cudafft.h"
#include "random_distr.h"

#include <stdint.h>
#include "cudaImageList.h"
#include "QueuedCUDATracker.h"

double getPreciseTime()
{
	uint64_t freq, time;

	QueryPerformanceCounter((LARGE_INTEGER*)&time);
	QueryPerformanceFrequency((LARGE_INTEGER*)&freq);

	return (double)time / (double)freq;
}





std::string getPath(const char *file)
{
	std::string s = file;
	int pos = s.length()-1;
	while (pos>0 && s[pos]!='\\' && s[pos]!= '/' )
		pos--;
	
	return s.substr(0, pos);
}


int main(int argc, char *argv[])
{
//	testLinearArray();
	int repeat = 10;
	int xcorProfileLen = 128, xcorProfileWidth = 16;

	std::string path = getPath(argv[0]);

	cudaDeviceProp prop;
	cudaGetDeviceProperties(&prop, 0);

	float t_gen=0, t_com=0, t_xcor=0;

	cudaEvent_t gen_start, gen_end, com_start, com_end, xcor_end;
	cudaEventCreate(&gen_start);
	cudaEventCreate(&gen_end);
	cudaEventCreate(&com_start);
	cudaEventCreate(&com_end);
	cudaEventCreate(&xcor_end);

	// Create some space for images
	cudaImageList images = cudaImageList::alloc(170,150, 2048);
	dbgprintf("Image memory used: %d bytes\n", images.totalsize());
	float3* d_pos;
	cudaMalloc(&d_pos, sizeof(float3)*images.count);
	float2* d_com;
	cudaMalloc(&d_com, sizeof(float2)*images.count);
	float2* d_xcor;
	cudaMalloc(&d_xcor, sizeof(float2)*images.count);

	float3* positions = new float3[images.count];
	for(int i=0;i<images.count;i++) {
		float xp = images.w/2+(rand_uniform<float>() - 0.5) * 5;
		float yp = images.h/2+(rand_uniform<float>() - 0.5) * 5;
		positions[i] = make_float3(xp, yp, 10);
	}
	cudaMemcpy(d_pos, positions, sizeof(float3)*images.count, cudaMemcpyHostToDevice);
	double err=0.0;

	QTrkSettings cfg;
	QueuedCUDATracker qtrk(&cfg);

	for (int k=0;k<repeat;k++) {
		cudaEventRecord(gen_start);
		qtrk.GenerateImages(images, d_pos);
		cudaEventRecord(gen_end);

		cudaEventRecord(com_start);
		qtrk.ComputeBgCorrectedCOM(images, d_com);
		cudaEventRecord(com_end);
		cudaEventSynchronize(com_end);

		float t_gen0, t_com0, t_xcor0;
		cudaEventElapsedTime(&t_gen0, gen_start, gen_end);
		t_gen+=t_gen0;
		cudaEventElapsedTime(&t_com0, com_start, com_end);
		t_com+=t_com0;
		std::vector<float2> com(images.count);
		cudaMemcpyAsync(&com[0], d_com, sizeof(float2)*images.count, cudaMemcpyDeviceToHost);

		qtrk.Compute1DXCor(images, d_com, d_xcor);
		cudaEventRecord(xcor_end);
		cudaEventSynchronize(xcor_end);
		cudaEventElapsedTime(&t_xcor0, com_end, xcor_end);
		t_xcor+=t_xcor0;

		for (int i=0;i<images.count;i++) {
			float dx = (com[i].x-positions[i].x);
			float dy = (com[i].y-positions[i].y);
			err += sqrt(dx*dx+dy*dy);
		}
	}


	int N = images.count*repeat*1000; // times are in ms
	dbgprintf("COM error: %f pixels\n", err/(images.count*repeat));
	dbgprintf("Image generating: %f img/s. COM computation: %f img/s. 1D XCor: %f img/s\n", N/t_gen, N/t_com, N/t_xcor);
	cudaFree(d_com);
	cudaFree(d_pos);
	images.free();

	cudaEventDestroy(gen_start); cudaEventDestroy(gen_end); 
	cudaEventDestroy(com_start); cudaEventDestroy(com_end); 
	
	return 0;
}
