#include"functions.cu"
#include<vector>

#ifndef NNET
#define NNET

/*
input is of dimension N x D : N = batch size and D = data dimension
*/

class neural_network {


	std :: vector<matrix *> weight_arr;
	std :: vector<matrix *> biases_arr;
	std :: vector<matrix *> output_arr;
	std :: vector<matrix *> activation_arr;
	std :: vector<matrix *> gradient_arr;

	matrix *mseLossDiff = NULL;
	matrix *mseLoss = NULL;
	matrix *singleLoss = NULL ;
	matrix *transPoseSpace = NULL;
	matrix *reductionMat = NULL;

	int batch_size, input_size, output_dim;
	int activation = FN_SIGM;
	int dactivation = FN_DSIGM;

	bool use_bias = false;

	public:

	void forward(matrix *data,bool updates = false) {

		data -> storeCuda();

		if(data -> height != batch_size || data -> width != input_size) {
			printf(" Input Data dimension mismatch required %d %d given %d %d",
				batch_size,input_size,data -> height,data -> width);
			return;
		}
		int i = 0;

		if(use_bias) 
			cuda_matmul(data,weight_arr[i],biases_arr[i],output_arr[i],updates);
		else
			cuda_matmul(data,weight_arr[i],output_arr[i],updates);
		cuda_function(output_arr[i],activation_arr[i],activation,updates);
		
		for(i += 1; i < weight_arr.size(); i++) {
			if(use_bias) 
				cuda_matmul(activation_arr[i-1],weight_arr[i],biases_arr[i],output_arr[i],updates);
			else
				cuda_matmul(activation_arr[i-1],weight_arr[i],output_arr[i],updates);
			cuda_function(output_arr[i],activation_arr[i],activation,updates);
		}	
	}

	void MSELossDiff(matrix *labels,bool updates = false) {

		labels -> storeCuda();

		matrix *final = activation_arr[activation_arr.size()-1];
		if(final -> height != labels -> height || final -> width != labels -> width) {
			printf(" Input Data dimension mismatch required %d %d given %d %d",
				final -> height,final -> width,labels -> height,labels -> width);
			return;
		}
		// printf("\n==================\n");
		// labels -> print();
		// printf("\n==================\n");
		// final -> print();
		// printf("\n=====================\n");
		cuda_vecDiff(labels,final,mseLossDiff,updates);

	}

	double returnSingleLoss() {
		cuda_hadamard(mseLossDiff,mseLossDiff,mseLoss);
		cuda_reduce(mseLoss,singleLoss,OP_ADD,1,true);
		double sum = 0;
		for(int i = 0; i < singleLoss -> width; i++) {
			//printf("%lf",singleLoss -> mat[i]);
			sum += singleLoss -> mat[i];
		}
		return sum/(batch_size * output_dim);
	}

	void backprop(matrix *data,double lrate,bool updates = false) {

		data -> storeCuda();

		int i = activation_arr.size() - 1;
		matrix *inp,*err = mseLossDiff;

		for(int i = activation_arr.size()-1; i >= 0; i--) {

			if(i == 0) inp = data;
			else inp = activation_arr[i-1];
			//error 
			cuda_function(output_arr[i],output_arr[i],dactivation,updates);
			cuda_hadamard(err,output_arr[i],output_arr[i],updates);

			//weight update
			cuda_transpose(inp,transPoseSpace,updates);
			transPoseSpace -> height = inp -> width;
			transPoseSpace -> width = inp -> height;
			cuda_matmul(transPoseSpace,output_arr[i],gradient_arr[i],updates);
			cuda_operation(gradient_arr[i],gradient_arr[i],lrate / batch_size,OP_MUL,updates);


			//update bias
			if(use_bias) {
				reductionMat -> width = err -> width;
				cuda_reduce(err,reductionMat,OP_ADD,1,updates);
				cuda_operation(reductionMat,reductionMat,lrate / batch_size,OP_MUL,updates);
				cuda_vecADD(biases_arr[i],reductionMat,biases_arr[i],updates);
			}

			//partial error at prev level
			if(i > 0) {
				cuda_transpose(weight_arr[i],transPoseSpace,updates);
				transPoseSpace -> height = weight_arr[i] -> width;
				transPoseSpace -> width = weight_arr[i] -> height;
				cuda_matmul(err,transPoseSpace,activation_arr[i-1],updates);
				err = activation_arr[i-1];
			}
		}

		for(int i = 0; i < gradient_arr.size(); i++) {
			cuda_vecADD(weight_arr[i],gradient_arr[i],weight_arr[i],updates);
		}

	}

	//public:

	void init(std::vector<int> nodeList,int bsize, 
		bool use_bias=true,double mean = 0,double std = 1) {

		//Re initialize all data structures if three exists a previous initialization
		for(int i = 0; i < weight_arr.size(); i++) {

			weight_arr[i] -> freeCuda();
			weight_arr[i] -> ~matrix();
			biases_arr[i] -> freeCuda();
			biases_arr[i] -> ~matrix();
			output_arr[i] -> freeCuda();
			output_arr[i] -> ~matrix();
			activation_arr[i] -> freeCuda();
			activation_arr[i] -> ~matrix();
		}

		weight_arr.clear();
		output_arr.clear();
		activation_arr.clear();
		biases_arr.clear();
		if(mseLoss) {
			mseLoss -> freeCuda();
			mseLoss -> ~matrix();
			mseLossDiff -> freeCuda();
			mseLossDiff -> ~matrix();
			singleLoss -> freeCuda();
			singleLoss -> ~matrix();
			transPoseSpace -> freeCuda();
			transPoseSpace -> ~matrix();
		}

		//new initialization 
		int max = 0;
		for(int i = 0; i < nodeList.size()-1; i++) {

			matrix *mat = new matrix, *omat = new matrix, 
				*amat = new matrix, *gmat = new matrix;
			mat -> init(nodeList[i],nodeList[i+1]);
			gaussianInitializer(mat,mean,std);

			if(use_bias) {
				matrix *bmat = new matrix;
				bmat -> init(1,nodeList[i+1]);
				gaussianInitializer(bmat,mean,std/2);
				biases_arr.push_back(bmat);
			}

			weight_arr.push_back(mat);
			output_arr.push_back(omat);
			activation_arr.push_back(amat);
			gradient_arr.push_back(gmat);

			if(nodeList[i] > max) max = nodeList[i];
		}

		mseLossDiff = new matrix;
		mseLoss = new matrix;
		singleLoss = new matrix;
		transPoseSpace = new matrix;
		reductionMat = new matrix;
		transPoseSpace -> init(max,bsize);
		reductionMat -> init(1,max);

		batch_size = bsize;
		this -> activation = activation;
		this -> use_bias = use_bias;
		input_size = nodeList[0];
		output_dim = nodeList[nodeList.size()-1];

	}


	void trainModel(matrix *data, matrix *label,int epochs,double lrate,
		int printLoss = 1) {
		data -> storeCuda();
		label -> storeCuda();
		matrix *pdata = new matrix, *plabel = new matrix;

		for(int e = 0; e < epochs; e++) {
			printf("\nEpoch No %d \n",e+1);
			double avgEpochLoss = 0;
			for(int i = 0; i < data -> height; i += batch_size) {

				data -> rowSlice(pdata,i,i+batch_size);
				label -> rowSlice(plabel,i,i+batch_size);
				forward(pdata);
				MSELossDiff(plabel);
				if(printLoss) {
					double Loss = returnSingleLoss();
					if(printLoss > 1)
						printf("%lf\n",Loss);
					avgEpochLoss += Loss;
				}
				backprop(pdata,lrate);
			}
			if(printLoss)
				printf("  Average Epoch Loss %8.10lf",
					avgEpochLoss/(data -> height / batch_size));
		}
	}

	matrix *encode(matrix *data) {

		matrix *rmat = new matrix;
		rmat -> init(data -> height,
			activation_arr[(int)(activation_arr.size()/2 -1)] -> width);
		matrix *pdata = new matrix;
		data -> storeCuda();

		for(int i = 0; i < data -> height; i += batch_size) {
			
			data -> rowSlice(pdata,i,i+batch_size);
			forward(pdata);
			matrix *emat = activation_arr[(int)(activation_arr.size()/2 -1)];
			emat -> updateCuda();
			for(int j = 0; j < batch_size; j++) {
				for(int k = 0; k < emat -> width; k++) {
					//printf("%lf\n",emat -> mat[j*emat -> width + k]);
					rmat -> mat[(j+i)*rmat -> width + k] = 
						emat -> mat[j*emat -> width + k];
				}
			}
		}
		return rmat;
	}

	void print_weights() {

		for(int i = 0; i < weight_arr.size(); i++) {
			weight_arr[i] -> updateCuda();
			weight_arr[i] -> print_shape();
			weight_arr[i] -> print();
		}
	}

	void print_biases() {
		for(int i = 0; i < biases_arr.size(); i++) {
			biases_arr[i] -> updateCuda();
			biases_arr[i] -> print_shape();
			biases_arr[i] -> print();
		}
	}

	void print_outputs() {
		for(int i = 0; i < output_arr.size(); i++) {
			output_arr[i] -> updateCuda();
			output_arr[i] -> print_shape();
			output_arr[i] -> print();
		}
	}

	void print_activations() {
		for(int i = 0; i < activation_arr.size(); i++) {
			activation_arr[i] -> updateCuda();
			activation_arr[i] -> print_shape();
			activation_arr[i] -> print();
		}
	}

	void printLossMat() {
		mseLoss -> updateCuda();
		mseLoss -> print_shape();
		mseLoss -> print();
	}
};

#endif