#include<iostream>
#include<cstdio>
#include<cstdlib>
#include<random>
#include<chrono>

using namespace std;

#define PREC "%6.2lf"

#ifndef MATRIX 
#define MATRIX
class matrix {

	public:
	double *mat = NULL;
	int height,width;
	bool isUpdated = false;
	double *cudaMat = NULL;
	bool isCopy = false;

	void init(int height,int width,double **imat = NULL) {
		this -> height = height;
		this -> width = width;
		mat = (double *)calloc(height*width,sizeof(double));
		if(imat) {
			for(int i = 0; i < height; i++) {
				for(int j = 0; j < width; j++) 
					mat[i*width + j] = imat[i][j];
			}
		}

	}

	double get(int i,int j) {
		if(isUpdated == false) {
			double *val = new double;
			cudaMemcpy(val,&cudaMat[i * width + j],sizeof(double),cudaMemcpyDeviceToHost);
			return *val;
		}
		else return mat[i * width + j];
	}

	void set(int i,int j,double val) {
		cudaMemcpy(&cudaMat[i * width +j],&val,sizeof(double),cudaMemcpyHostToDevice);
		mat[i * width + j] = val;
	}

	void print() {
		for(int i = 0; i < height; i++) {
			for(int j = 0; j < width; j++) {
				printf(PREC,mat[i*width + j]);
			}
			printf("\n");
		}
	}

	void print_shape() {
		printf("\n(%d,%d)\n",height,width);
	}

	~matrix() {
		if(mat) {
			free(mat);
			mat = NULL;
		}
		height = width = 0;
	}

	void storeCuda() {
		if(cudaMat == NULL)
			cudaMalloc(&cudaMat,height * width * sizeof(double));
		cudaMemcpy(cudaMat,mat,height * width * sizeof(double),cudaMemcpyHostToDevice);
	}

	void updateCuda() {
		if(cudaMat && mat) {
			cudaDeviceSynchronize();
			//cudaThreadSynchronize();
			cudaMemcpy(mat,cudaMat,height * width * sizeof(double),cudaMemcpyDeviceToHost);
			isUpdated = true;
		}
	}

	void freeCuda() {
		if(cudaMat) {
			updateCuda();
			cudaFree(cudaMat);
			cudaMat = NULL;
		}
	}

	matrix *rowSlice(matrix *mat, int rows,int rowe) {

		updateCuda();
		mat -> height = rowe - rows;
		mat -> width = width;
		mat -> mat = this -> mat + rows * width;
		mat -> isCopy = true;
		if(cudaMat) {
			mat -> cudaMat = cudaMat + rows * width;
			isUpdated = true;
		}
		return mat;
	}

};

matrix *loadFromFile(char *loc) {
	FILE *ptr = fopen(loc,"r");
	matrix *mat = new matrix;
	fscanf(ptr,"%d %d",&(mat -> height),&(mat -> width));
	mat -> mat = new double[mat -> height * mat -> width];
	for(int i = 0; i < mat -> height; i++) {
		for(int j = 0; j < mat -> width; j++) {
			fscanf(ptr,"%lf",&mat -> mat[i * mat -> width + j]);
		}
	}
	fclose(ptr);
	return mat;
}

matrix *matrix_multi(matrix *mat1,matrix *mat2) {

	if(mat1 -> width != mat2 -> height) return NULL;
	matrix *new_mat = new matrix;
	new_mat -> init(mat1 -> height,mat2 -> width);
	for(int i = 0; i < mat1 -> height; i++) {
		for(int j = 0; j < mat2 -> width; j++) {
			double sum = 0;
			for(int k = 0; k < mat1 -> width; k++)
				sum += mat1 -> get(i,k)*mat2 -> get(k,j);
			new_mat -> set(i,j,sum);
		}
	}

	return new_mat;
}

void gaussianInitializer(matrix *mat,double mean = 0, double std = 1) {

	if(!mat -> mat) {
		printf("Uninitialized Matrix\n");
		return;
	}

	std :: default_random_engine gen;
	gen.seed(std::chrono::system_clock::now().time_since_epoch().count());
	std :: normal_distribution<double> dist(mean,std);

	for (int i = 0; i < mat -> height*mat->width;i++) {
		mat -> mat[i] = dist(gen);
	}
}


void readCSV(matrix *mat , matrix *out_mat, int height,int width,bool flag = false,int label = 0){
        
        FILE* f1 = fopen("Data20000","r");

        char rec[100000];

        width = width - 1;
        mat -> init(height,width);
        out_mat -> init(height,1);

        int i=0;
        while(fscanf(f1, "%s", rec) != EOF){
            //cout<<i<<endl;
            if(!flag){
                    flag=true;
                    continue;
            }
	        char *p = strtok (rec, ",");
	        int j=0,k=0;
	        while (p != NULL){
	            if(j==label){

	                out_mat->mat[i] = atoi(p);
	                j++;
	                continue;
	            }
	            //printf("%d %d\n",k,j);
	            mat->mat[i*width + k++]=atoi(p);

	            p = strtok (NULL, ",");
	            j++;
            }
            i++;
        }
        cout<<"Loading done\n";

}

void storeAsCSV(matrix *mat,char *loc) {

	FILE *fp = fopen(loc,"w");
	for(int i = 0; i < mat -> height; i++) {
		for(int j = 0; j < mat -> width-1;j++) {
			fprintf(fp, "%6.4lf,", mat -> mat[i*mat->width + j]);
		}
		fprintf(fp, "%6.4lf\n", mat -> mat[i*mat->width + mat->width-1]);
	}
	fclose(fp);
}

matrix *point_multi(matrix *mat1,matrix *mat2) {

	matrix *hmat = new matrix;
	hmat -> init(mat1 -> height, mat1 -> width);
	for(int i = 0; i < mat1 -> height; i++) {
		for(int j = 0; j < mat1 -> width; j++) {
			hmat -> mat[i*mat1 -> width + j] = 
				mat1 -> mat[i*mat1 -> width + j]*mat2 -> mat[i*mat1 -> width + j];
		}
	}

	return hmat;
}

#endif