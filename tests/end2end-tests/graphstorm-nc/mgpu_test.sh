#!/bin/bash

service ssh restart

DGL_HOME=/root/dgl
GS_HOME=$(pwd)
NUM_TRAINERS=4
NUM_INFERs=2
export PYTHONPATH=$GS_HOME/python/
cd $GS_HOME/training_scripts/gsgnn_np
echo "127.0.0.1" > ip_list.txt
cd $GS_HOME/inference_scripts/np_infer
echo "127.0.0.1" > ip_list.txt


error_and_exit () {
	# check exec status of launch.py
	status=$1
	echo $status

	if test $status -ne 0
	then
		exit -1
	fi
}

echo "**************dataset: MovieLens classification, RGCN layer: 1, node feat: fixed HF BERT, BERT nodes: movie, inference: mini-batch save model save emb node"
python3 -m graphstorm.run.gs_node_classification --workspace $GS_HOME/training_scripts/gsgnn_np/ --num-trainers $NUM_TRAINERS --num-servers 1 --num-samplers 0 --part-config /data/movielen_100k_train_val_1p_4t/movie-lens-100k.json --ip-config ip_list.txt --ssh-port 2222 --cf ml_nc.yaml --save-model-path /data/gsgnn_nc_ml/ --topk-model-to-save 1 --save-embed-path /data/gsgnn_nc_ml/emb/ --num-epochs 3 --logging-file /tmp/train_log.txt --logging-level debug

error_and_exit $?

# check prints
cnt=$(grep "save_embed_path: /data/gsgnn_nc_ml/emb/" /tmp/train_log.txt | wc -l)
if test $cnt -lt 1
then
    echo "We use SageMaker task tracker, we should have save_embed_path"
    exit -1
fi

cnt=$(grep "save_model_path: /data/gsgnn_nc_ml/" /tmp/train_log.txt | wc -l)
if test $cnt -lt 1
then
    echo "We use SageMaker task tracker, we should have save_model_path"
    exit -1
fi

bst_cnt=$(grep "Best Test accuracy" /tmp/train_log.txt | wc -l)
if test $bst_cnt -lt 1
then
    echo "We use SageMaker task tracker, we should have Best Test accuracy"
    exit -1
fi

cnt=$(grep "Test accuracy" /tmp/train_log.txt | wc -l)
if test $cnt -lt $((1+$bst_cnt))
then
    echo "We use SageMaker task tracker, we should have Test accuracy"
    exit -1
fi

bst_cnt=$(grep "Best Validation accuracy" /tmp/train_log.txt | wc -l)
if test $bst_cnt -lt 1
then
    echo "We use SageMaker task tracker, we should have Best Validation accuracy"
    exit -1
fi

cnt=$(grep "Validation accuracy" /tmp/train_log.txt | wc -l)
if test $cnt -lt $((1+$bst_cnt))
then
    echo "We use SageMaker task tracker, we should have Validation accuracy"
    exit -1
fi

cnt=$(grep "Best Iteration" /tmp/train_log.txt | wc -l)
if test $cnt -lt 1
then
    echo "We use SageMaker task tracker, we should have Best Iteration"
    exit -1
fi

cnt=$(ls -l /data/gsgnn_nc_ml/ | grep epoch | wc -l)
if test $cnt != 1
then
    echo "The number of save models $cnt is not equal to the specified topk 1"
    exit -1
fi

best_epoch=$(grep "successfully save the model to" /tmp/train_log.txt | tail -1 | tr -d '\n' | tail -c 1)
echo "The best model is saved in epoch $best_epoch"

rm /tmp/train_log.txt

echo "**************dataset: Movielens, do inference on saved model"
python3 -m graphstorm.run.gs_node_classification --inference --workspace $GS_HOME/inference_scripts/np_infer/ --num-trainers $NUM_INFERs --num-servers 1 --num-samplers 0 --part-config /data/movielen_100k_train_val_1p_4t/movie-lens-100k.json --ip-config ip_list.txt --ssh-port 2222 --cf ml_nc_infer.yaml --use-mini-batch-infer false  --save-embed-path /data/gsgnn_nc_ml/infer-emb/ --restore-model-path /data/gsgnn_nc_ml/epoch-$best_epoch/ --save-prediction-path /data/gsgnn_nc_ml/prediction/ --logging-file /tmp/log.txt

error_and_exit $?

cnt=$(grep "| Test accuracy" /tmp/log.txt | wc -l)
if test $cnt -ne 1
then
    echo "We do test, should have test accuracy"
    exit -1
fi

bst_cnt=$(grep "Best Test accuracy" /tmp/log.txt | wc -l)
if test $bst_cnt -lt 1
then
    echo "We use SageMaker task tracker, we should have Best Test accuracy"
    exit -1
fi

bst_cnt=$(grep "Best Validation accuracy" /tmp/log.txt | wc -l)
if test $bst_cnt -lt 1
then
    echo "We use SageMaker task tracker, we should have Best Validation accuracy"
    exit -1
fi

cnt=$(grep "Validation accuracy" /tmp/log.txt | wc -l)
if test $cnt -lt 1
then
    echo "We use SageMaker task tracker, we should have Validation accuracy"
    exit -1
fi

cnt=$(grep "Best Iteration" /tmp/log.txt | wc -l)
if test $cnt -lt 1
then
    echo "We use SageMaker task tracker, we should have Best Iteration"
    exit -1
fi

rm /tmp/log.txt

python3 $GS_HOME/tests/end2end-tests/check_infer.py --train_embout /data/gsgnn_nc_ml/emb/ --infer_embout /data/gsgnn_nc_ml/infer-emb/

error_and_exit $?

echo "**************dataset: Movielens, do inference on saved model with mini-batch-infer without test mask"
python3 -m graphstorm.run.gs_node_classification --inference --workspace $GS_HOME/inference_scripts/np_infer/ --num-trainers $NUM_INFERs --num-servers 1 --num-samplers 0 --part-config /data/movielen_100k_train_notest_1p_4t/movie-lens-100k.json --ip-config ip_list.txt --ssh-port 2222 --cf ml_nc_infer.yaml --use-mini-batch-infer true  --save-embed-path /data/gsgnn_nc_ml/mini-infer-emb/ --restore-model-path /data/gsgnn_nc_ml/epoch-$best_epoch/ --save-prediction-path /data/gsgnn_nc_ml/prediction/ --no-validation true

error_and_exit $?

python3 $GS_HOME/tests/end2end-tests/check_infer.py --train_embout /data/gsgnn_nc_ml/emb/ --infer_embout /data/gsgnn_nc_ml/mini-infer-emb --mini-batch-infer

error_and_exit $?

echo "**************dataset: MovieLens classification, RGCN layer: 1, node feat: fixed HF BERT, BERT nodes: movie, inference: mini-batch save model save emb node, early stop"
python3 -m graphstorm.run.gs_node_classification --workspace $GS_HOME/training_scripts/gsgnn_np/ --num-trainers $NUM_TRAINERS --num-servers 1 --num-samplers 0 --part-config /data/movielen_100k_train_val_1p_4t/movie-lens-100k.json --ip-config ip_list.txt --ssh-port 2222 --cf ml_nc.yaml --save-model-path /data/gsgnn_nc_ml/ --topk-model-to-save 3 --save-embed-path /data/gsgnn_nc_ml/emb/ --use-early-stop True --early-stop-burnin-rounds 2 -e 20 --early-stop-rounds 3 --early-stop-strategy consecutive_increase --logging-file /tmp/exec.log --logging-level debug

error_and_exit $?

# check early stop
cnt=$(cat /tmp/exec.log | grep "Evaluation step" | wc -l)
if test $cnt -eq 20
then
	echo "Early stop should work, but it didn't"
	exit -1
fi

rm /tmp/exec.log

if test $cnt -le 4
then
	echo "Need at least 5 iters"
	exit -1
fi

cnt=$(ls -l /data/gsgnn_nc_ml/ | grep epoch | wc -l)
if test $cnt != 3
then
    echo "The number of save models $cnt is not equal to the specified topk 3"
    exit -1
fi

rm -fr /data/gsgnn_nc_ml/*

echo "**************dataset: MovieLens classification, RGCN layer: 1, node feat: BERT nodes: movie, user inference: mini-batch save model save emb node"
python3 -m graphstorm.run.gs_node_classification --workspace $GS_HOME/training_scripts/gsgnn_np/ --num-trainers $NUM_TRAINERS --num-servers 1 --num-samplers 0 --part-config /data/movielen_100k_lm_encoder_train_val_1p_4t/movie-lens-100k-text.json --ip-config ip_list.txt --ssh-port 2222 --cf ml_nc_utext.yaml  --save-model-path /data/gsgnn_nc_ml_text/ --topk-model-to-save 1 --save-embed-path /data/gsgnn_nc_ml_text/emb/ --num-epochs 3 --logging-file /tmp/train_log.txt --cache-lm-embed true

error_and_exit $?

cnt=$(ls -l /data/gsgnn_nc_ml_text/ | grep epoch | wc -l)
if test $cnt != 1
then
    echo "The number of save models $cnt is not equal to the specified topk 1"
    exit -1
fi

best_epoch=$(grep "successfully save the model to" /tmp/train_log.txt | tail -1 | tr -d '\n' | tail -c 1)
echo "The best model is saved in epoch $best_epoch"

rm /tmp/train_log.txt

echo "*************use cached LM embeddings"
# Run the model training again and this time it should load the BERT embeddings saved
# in the previous run.
python3 -m graphstorm.run.gs_node_classification --workspace $GS_HOME/training_scripts/gsgnn_np/ --num-trainers $NUM_TRAINERS --num-servers 1 --num-samplers 0 --part-config /data/movielen_100k_lm_encoder_train_val_1p_4t/movie-lens-100k-text.json --ip-config ip_list.txt --ssh-port 2222 --cf ml_nc_utext.yaml --num-epochs 3 --logging-file /tmp/train_log.txt --cache-lm-embed true

error_and_exit $?

rm /tmp/train_log.txt

echo "**************dataset: Movielens, do inference on saved model, decoder: dot"
python3 -m graphstorm.run.gs_node_classification --inference --workspace $GS_HOME/inference_scripts/np_infer/ --num-trainers $NUM_INFERs --num-servers 1 --num-samplers 0 --part-config /data/movielen_100k_lm_encoder_train_val_1p_4t/movie-lens-100k-text.json --ip-config ip_list.txt --ssh-port 2222 --cf ml_nc_text_infer.yaml --use-mini-batch-infer false   --save-embed-path /data/gsgnn_nc_ml_text/infer-emb/ --restore-model-path /data/gsgnn_nc_ml_text/epoch-$best_epoch/ --save-prediction-path /data/gsgnn_nc_ml_text/prediction/ --logging-file /tmp/log.txt --logging-level debug

error_and_exit $?

cnt=$(grep "| Test accuracy" /tmp/log.txt | wc -l)
if test $cnt -ne 1
then
    echo "We do test, should have test accuracy"
    exit -1
fi

rm /tmp/log.txt

python3 $GS_HOME/tests/end2end-tests/check_infer.py --train_embout /data/gsgnn_nc_ml_text/emb/ --infer_embout /data/gsgnn_nc_ml_text/infer-emb/

error_and_exit $?

echo "**************dataset: Movielens, use GLEM to restore checkpoint saved by GSgnnNodePredictionTrainer and do inference"
# create softlinks for GLEM
mkdir -p /data/gsgnn_nc_ml_text/epoch-$best_epoch/GLEM
ln -s /data/gsgnn_nc_ml_text/epoch-$best_epoch /data/gsgnn_nc_ml_text/epoch-$best_epoch/GLEM/LM
ln -s /data/gsgnn_nc_ml_text/epoch-$best_epoch /data/gsgnn_nc_ml_text/epoch-$best_epoch/GLEM/GNN

python3 -m graphstorm.run.gs_node_classification --workspace $GS_HOME/training_scripts/gsgnn_np/ --num-trainers $NUM_INFERs --num-servers 1 --num-samplers 0 --part-config /data/movielen_100k_lm_encoder_train_val_1p_4t/movie-lens-100k-text.json --ip-config ip_list.txt --ssh-port 2222 --cf ml_nc_utext_glem.yml --use-mini-batch-infer true --restore-model-path /data/gsgnn_nc_ml_text/epoch-$best_epoch/GLEM --restore-model-layers embed --inference 

error_and_exit $?

rm -fr /data/gsgnn_nc_ml_text/*

echo "**************dataset: MovieLens classification, RGCN layer: 1, node feat: BERT nodes: movie, user, with warmup inference: mini-batch save model save emb node"
python3 -m graphstorm.run.gs_node_classification --workspace $GS_HOME/training_scripts/gsgnn_np/ --num-trainers $NUM_TRAINERS --num-servers 1 --num-samplers 0 --part-config /data/movielen_100k_lm_encoder_train_val_1p_4t/movie-lens-100k-text.json --ip-config ip_list.txt --ssh-port 2222 --cf ml_nc_utext.yaml --save-model-path /data/gsgnn_nc_ml_text/ --topk-model-to-save 1 --save-embed-path /data/gsgnn_nc_ml_text/emb/ --num-epochs 3 --freeze-lm-encoder-epochs 1 --logging-file /tmp/train_log.txt

error_and_exit  $?

cnt=$(ls -l /data/gsgnn_nc_ml_text/ | grep epoch | wc -l)
if test $cnt != 1
then
    echo "The number of save models $cnt is not equal to the specified topk 1"
    exit -1
fi

best_epoch=$(grep "successfully save the model to" /tmp/train_log.txt | tail -1 | tr -d '\n' | tail -c 1)
echo "The best model is saved in epoch $best_epoch"

rm /tmp/train_log.txt

echo "**************dataset: Movielens, do inference on saved model, decoder: dot"
python3 -m graphstorm.run.gs_node_classification --inference --workspace $GS_HOME/inference_scripts/np_infer/ --num-trainers $NUM_INFERs --num-servers 1 --num-samplers 0 --part-config /data/movielen_100k_lm_encoder_train_val_1p_4t/movie-lens-100k-text.json --ip-config ip_list.txt --ssh-port 2222 --cf ml_nc_text_infer.yaml --use-mini-batch-infer false --save-embed-path /data/gsgnn_nc_ml_text/infer-emb/ --restore-model-path /data/gsgnn_nc_ml_text/epoch-$best_epoch/ --save-prediction-path /data/gsgnn_nc_ml_text/prediction/ --logging-file /tmp/log.txt --logging-level debug

error_and_exit $?

cnt=$(grep "| Test accuracy" /tmp/log.txt | wc -l)
if test $cnt -ne 1
then
    echo "We do test, should have test accuracy"
    exit -1
fi

rm /tmp/log.txt

python3 $GS_HOME/tests/end2end-tests/check_infer.py --train_embout /data/gsgnn_nc_ml_text/emb/ --infer_embout /data/gsgnn_nc_ml_text/infer-emb/

error_and_exit $?
rm -fr /data/gsgnn_nc_ml_text/*

echo "**************dataset: MovieLens classification, RGCN layer: 1, node feat: BERT nodes: movie, user inference: mini-batch save model save emb node, train_nodes 0"
python3 -m graphstorm.run.gs_node_classification --workspace $GS_HOME/training_scripts/gsgnn_np/ --num-trainers $NUM_TRAINERS --num-servers 1 --num-samplers 0 --part-config /data/movielen_100k_lm_encoder_train_val_1p_4t/movie-lens-100k-text.json --ip-config ip_list.txt --ssh-port 2222 --cf ml_nc_utext.yaml  --save-model-path /data/gsgnn_nc_ml_text/ --topk-model-to-save 1 --save-embed-path /data/gsgnn_nc_ml_text/emb/ --num-epochs 3 --lm-train-nodes 0

error_and_exit $?
rm -fr /data/gsgnn_nc_ml_text/*

echo "**************dataset: MovieLens classification, RGCN layer: 1, node feat: RoBERTa nodes: movie, user inference: mini-batch save model save emb node, train_nodes 0"
python3 -m graphstorm.run.gs_node_classification --workspace $GS_HOME/training_scripts/gsgnn_np/ --num-trainers $NUM_TRAINERS --num-servers 1 --num-samplers 0 --part-config /data/movielen_100k_roberta_encoder_train_val_1p_4t/movie-lens-100k-text.json --ip-config ip_list.txt --ssh-port 2222 --cf ml_nc_utext_roberta.yaml  --save-model-path /data/gsgnn_nc_ml_text/ --topk-model-to-save 1 --save-embed-path /data/gsgnn_nc_ml_text/emb/ --num-epochs 3 --lm-train-nodes 0

error_and_exit $?
rm -fr /data/gsgnn_nc_ml_text/*

echo "**************dataset: MovieLens classification, GLEM co-training, RGCN layer: 1, node feat: BERT nodes: movie, user inference: full-graph save model save emb node"
python3 -m graphstorm.run.gs_node_classification --workspace $GS_HOME/training_scripts/gsgnn_np/ --num-trainers $NUM_TRAINERS --num-servers 1 --num-samplers 0 --part-config /data/movielen_100k_lm_encoder_train_val_1p_4t/movie-lens-100k-text.json --ip-config ip_list.txt --ssh-port 2222 --cf ml_nc_utext_glem.yml  --save-model-path /data/gsgnn_nc_ml_text/ --topk-model-to-save 1 --num-epochs 3

error_and_exit $?

cnt=$(ls -l /data/gsgnn_nc_ml_text/ | grep epoch | wc -l)
if test $cnt != 1
then
    echo "The number of save models $cnt is not equal to the specified topk 1"
    exit -1
fi

rm -fr /data/gsgnn_nc_ml_text/*

echo "**************dataset: MovieLens semi-supervised classification, GLEM co-training, RGCN layer: 1, node feat: BERT nodes: movie, user inference: mini-batch save model"
python3 -m graphstorm.run.gs_node_classification --workspace $GS_HOME/training_scripts/gsgnn_np/ --num-trainers $NUM_TRAINERS --num-servers 1 --num-samplers 0 --part-config /data/movielen_100k_lm_encoder_train_val_1p_4t/movie-lens-100k-text.json --ip-config ip_list.txt --ssh-port 2222 --cf ml_nc_utext_glem.yml  --save-model-path /data/gsgnn_nc_ml_text/ --topk-model-to-save 1 --num-epochs 2 --use-pseudolabel true

error_and_exit $?

cnt=$(ls -l /data/gsgnn_nc_ml_text/ | grep epoch | wc -l)
if test $cnt != 1
then
    echo "The number of save models $cnt is not equal to the specified topk 1"
    exit -1
fi

best_epoch=$(ls /data/gsgnn_nc_ml_text/ | grep epoch)
echo "**************dataset: MovieLens node classification, GLEM loads GLEM trained checkpoints, RGCN layer: 1, node feat: BERT nodes: movie, user inference: mini-batch save model"
python3 -m graphstorm.run.gs_node_classification --workspace $GS_HOME/training_scripts/gsgnn_np/ --num-trainers $NUM_TRAINERS --num-servers 1 --num-samplers 0 --part-config /data/movielen_100k_lm_encoder_train_val_1p_4t/movie-lens-100k-text.json --ip-config ip_list.txt --ssh-port 2222 --cf ml_nc_utext_glem.yml  --restore-model-path /data/gsgnn_nc_ml_text/$best_epoch --restore-model-layers embed,decoder --inference --use-mini-batch-infer false --logging-file /tmp/full_graph_inf.txt

error_and_exit $?

python3 -m graphstorm.run.gs_node_classification --workspace $GS_HOME/training_scripts/gsgnn_np/ --num-trainers $NUM_TRAINERS --num-servers 1 --num-samplers 0 --part-config /data/movielen_100k_lm_encoder_train_val_1p_4t/movie-lens-100k-text.json --ip-config ip_list.txt --ssh-port 2222 --cf ml_nc_utext_glem.yml  --restore-model-path /data/gsgnn_nc_ml_text/$best_epoch --restore-model-layers embed,decoder --inference --use-mini-batch-infer true --logging-file /tmp/mini_batch_inf.txt

error_and_exit $?

# assert same performance results from mini-batch and full-graph inference
perf_full=$(grep "Best Test accuracy" /tmp/full_graph_inf.txt | sed 's/^.*: //')
perf_mini=$(grep "Best Test accuracy" /tmp/mini_batch_inf.txt | sed 's/^.*: //')
if $perf_full != $perf_mini
then
    echo "The performance is different from full-graph and mini-batch inference!"
    exit -1
fi


rm -fr /data/gsgnn_nc_ml_text/*
rm /tmp/full_graph_inf.txt
rm /tmp/mini_batch_inf.txt

echo "**************dataset: MovieLens classification, RGCN layer: 1, node feat: fixed HF BERT, BERT nodes: movie, inference: mini-batch save model save emb node, Backend nccl"
python3 -m graphstorm.run.gs_node_classification --workspace $GS_HOME/training_scripts/gsgnn_np/ --num-trainers $NUM_TRAINERS --num-servers 1 --num-samplers 0 --part-config /data/movielen_100k_train_val_1p_4t/movie-lens-100k.json --ip-config ip_list.txt --ssh-port 2222 --cf ml_nc.yaml --save-model-path /data/gsgnn_nc_ml/ --num-epochs 1 --backend nccl --node-feat-name movie:title user:feat

error_and_exit $?
