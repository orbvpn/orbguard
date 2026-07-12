# OrbGuard ML Model Training Guide

This guide provides instructions for training the on-device machine learning models used by OrbGuard.

## Prerequisites

- Python 3.9+
- TensorFlow 2.x
- tensorflow-lite
- numpy, pandas, scikit-learn

```bash
pip install tensorflow tensorflow-datasets numpy pandas scikit-learn
```

## Models Overview

| Model | Purpose | Architecture | Target Size |
|-------|---------|--------------|-------------|
| scam_classifier | SMS/text scam detection | Bi-LSTM | ~5MB |
| url_classifier | Malicious URL detection | 1D CNN | ~3MB |
| app_risk | App risk assessment | Feed-forward NN | ~10MB |
| image_classifier | Phishing screenshot detection | MobileNetV3 | ~15MB |
| intent_model | Message intent extraction | BERT-Tiny | ~20MB |

## Training Datasets

### Scam Classifier
- **SMS Spam Collection** (UCI ML Repository)
- **Kaggle SMS Spam Dataset**
- **Custom phishing SMS samples** (curated from threat intelligence)

### URL Classifier
- **PhishTank** - phishing URLs
- **URLhaus** - malware URLs
- **OpenPhish** - phishing URLs
- **Alexa Top 1M** - benign URLs

### App Risk Model
- **Android malware datasets** (Drebin, AMD)
- **VirusTotal app metadata**
- **Google Play scraped metadata** (benign)

### Image Classifier
- **PhishIntention dataset**
- **Legitimate login page screenshots**

## Training Scripts

### 1. Scam Classifier

```python
import tensorflow as tf
from tensorflow.keras.preprocessing.text import Tokenizer
from tensorflow.keras.preprocessing.sequence import pad_sequences

# Load data
texts, labels = load_scam_dataset()

# Tokenize
tokenizer = Tokenizer(num_words=10000, oov_token='<OOV>')
tokenizer.fit_on_texts(texts)
sequences = tokenizer.texts_to_sequences(texts)
padded = pad_sequences(sequences, maxlen=128, padding='post', truncating='post')

# Build model
model = tf.keras.Sequential([
    tf.keras.layers.Embedding(10000, 128, input_length=128),
    tf.keras.layers.Bidirectional(tf.keras.layers.LSTM(64)),
    tf.keras.layers.Dropout(0.3),
    tf.keras.layers.Dense(32, activation='relu'),
    tf.keras.layers.Dropout(0.2),
    tf.keras.layers.Dense(2, activation='softmax')
])

model.compile(optimizer='adam', loss='categorical_crossentropy', metrics=['accuracy'])
model.fit(padded, labels, epochs=50, batch_size=32, validation_split=0.2)

# Convert to TFLite
converter = tf.lite.TFLiteConverter.from_keras_model(model)
converter.optimizations = [tf.lite.Optimize.DEFAULT]
converter.target_spec.supported_types = [tf.float16]
tflite_model = converter.convert()

with open('scam_classifier.tflite', 'wb') as f:
    f.write(tflite_model)
```

### 2. URL Classifier

```python
# Character-level URL encoding
def encode_url(url, max_len=200):
    encoded = [ord(c) % 256 for c in url[:max_len]]
    return encoded + [0] * (max_len - len(encoded))

# Build model
model = tf.keras.Sequential([
    tf.keras.layers.Embedding(256, 64, input_length=200),
    tf.keras.layers.Conv1D(128, 3, activation='relu'),
    tf.keras.layers.MaxPooling1D(2),
    tf.keras.layers.Conv1D(64, 3, activation='relu'),
    tf.keras.layers.GlobalMaxPooling1D(),
    tf.keras.layers.Dense(64, activation='relu'),
    tf.keras.layers.Dropout(0.3),
    tf.keras.layers.Dense(4, activation='softmax')
])
```

### 3. App Risk Model

```python
# Feature extraction from APK metadata
features = [
    'permission_count', 'dangerous_permissions', 'tracker_count',
    'ad_sdk_count', 'has_accessibility', 'has_device_admin',
    'uses_native_code', 'uses_reflection', 'min_sdk', 'target_sdk'
]

# Build model
model = tf.keras.Sequential([
    tf.keras.layers.Dense(256, activation='relu', input_shape=(50,)),
    tf.keras.layers.BatchNormalization(),
    tf.keras.layers.Dropout(0.3),
    tf.keras.layers.Dense(128, activation='relu'),
    tf.keras.layers.BatchNormalization(),
    tf.keras.layers.Dropout(0.2),
    tf.keras.layers.Dense(64, activation='relu'),
    tf.keras.layers.Dense(5, activation='softmax')
])
```

### 4. Image Classifier (Transfer Learning)

```python
# Use MobileNetV3 as base
base_model = tf.keras.applications.MobileNetV3Small(
    include_top=False,
    weights='imagenet',
    input_shape=(224, 224, 3)
)
base_model.trainable = False

model = tf.keras.Sequential([
    base_model,
    tf.keras.layers.GlobalAveragePooling2D(),
    tf.keras.layers.Dense(128, activation='relu'),
    tf.keras.layers.Dropout(0.3),
    tf.keras.layers.Dense(3, activation='softmax')
])

# Fine-tune after initial training
base_model.trainable = True
for layer in base_model.layers[:-20]:
    layer.trainable = False
```

## TFLite Conversion

```python
# Standard conversion with optimizations
converter = tf.lite.TFLiteConverter.from_keras_model(model)

# Enable optimizations
converter.optimizations = [tf.lite.Optimize.DEFAULT]

# For smaller models (float16 quantization)
converter.target_spec.supported_types = [tf.float16]

# For smallest models (int8 quantization - requires representative dataset)
def representative_dataset():
    for data in train_dataset.take(100):
        yield [tf.cast(data, tf.float32)]

converter.representative_dataset = representative_dataset
converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
converter.inference_input_type = tf.int8
converter.inference_output_type = tf.int8

tflite_model = converter.convert()
```

## Model Validation

Before deployment, models must pass:
1. **Accuracy threshold** - See model_specifications.json for minimum accuracy
2. **Size constraint** - Must be under target size
3. **Inference speed** - < 100ms on mid-range device
4. **False positive rate** - < 5% for critical detections

## Deployment

1. Run training script
2. Convert to TFLite
3. Validate performance
4. Generate SHA256 checksum
5. Upload to model server
6. Update version in model_specifications.json

## Fallback Behavior

All models have heuristic fallbacks that activate when:
- Model file not downloaded
- Model loading fails
- Inference error occurs

Heuristics are implemented in corresponding classifier files.
