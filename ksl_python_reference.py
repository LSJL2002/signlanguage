import argparse
import json
import cv2
import numpy as np
import mediapipe as mp
import onnxruntime as ort
from pathlib import Path

# --- 1. CONFIGURATION & MODEL PATHS ---
PROJECT_DIR = Path(__file__).resolve().parent
MODEL_DIR = PROJECT_DIR / "saved_models"
STAGE1_MODEL_PATH = MODEL_DIR / "stage1_model.onnx"
VOCAB_PATH = MODEL_DIR / "gloss_to_id.json"
STAGE2_ENCODER_PATH = MODEL_DIR / "encoder_model.onnx"
STAGE2_DECODER_PATH = MODEL_DIR / "decoder_model_quantized.onnx"
STAGE2_DECODER_FALLBACK_PATH = MODEL_DIR / "decoder_model.onnx"
KOBART_TOKENIZER_PATH = MODEL_DIR / "kobart_tokenizer.json"
KOBART_CONFIG_PATH = MODEL_DIR / "kobart_config.json"

# Pose order follows the original 11-point selection in preprocess.py.
R_SHOULDER_IDX = 2
L_SHOULDER_IDX = 5
POSE_NAMES = [
    "nose",
    "neck",
    "right_shoulder",
    "right_elbow",
    "right_wrist",
    "left_shoulder",
    "left_elbow",
    "left_wrist",
    "mid_hip",
    "right_hip",
    "left_hip",
]
LEGACY_FEATURE_WIDTH = 492

# AIHub's guideline defines FACE groups in this order: chin, right eyebrow,
# left eyebrow, nose, right pupil, left pupil, lips, right eye, left eye.
# These MediaPipe indices approximate those annotated groups; they are not an
# official AIHub-to-MediaPipe mapping.
FACE_CHIN_INDICES = [
    234, 93, 132, 58, 172, 136, 150, 149, 176, 152, 377, 400, 378, 379, 365,
    397, 288,
]
FACE_RIGHT_EYEBROW_INDICES = [70, 63, 105, 66, 107]
FACE_LEFT_EYEBROW_INDICES = [336, 296, 334, 293, 300]
FACE_NOSE_INDICES = [168, 6, 197, 195, 5, 4, 1, 19, 94]
FACE_RIGHT_PUPIL_INDICES = [468, 469, 470, 471, 472, 133]
FACE_LEFT_PUPIL_INDICES = [473, 474, 475, 476, 477, 362]
FACE_LIP_INDICES = [
    61, 185, 40, 39, 37, 0, 267, 269, 270, 409, 291, 375, 321, 405, 314,
    17, 84, 181, 91, 146,
]
FACE_RIGHT_EYE_CORNERS = (33, 133)
FACE_LEFT_EYE_CORNERS = (362, 263)


# --- 2. LOAD VOCABULARY & MODELS ---
print("Loading vocabulary and ONNX models...")
if not VOCAB_PATH.is_file():
    raise FileNotFoundError(f"Gloss vocabulary not found: {VOCAB_PATH}")
if not STAGE1_MODEL_PATH.is_file():
    raise FileNotFoundError(f"Stage 1 ONNX model not found: {STAGE1_MODEL_PATH}")
if not STAGE2_ENCODER_PATH.is_file():
    raise FileNotFoundError(f"Stage 2 KoBART encoder not found: {STAGE2_ENCODER_PATH}")
if not KOBART_TOKENIZER_PATH.is_file():
    raise FileNotFoundError(f"KoBART tokenizer not found: {KOBART_TOKENIZER_PATH}")
if not KOBART_CONFIG_PATH.is_file():
    raise FileNotFoundError(f"KoBART config not found: {KOBART_CONFIG_PATH}")
if not STAGE2_DECODER_PATH.is_file() and not STAGE2_DECODER_FALLBACK_PATH.is_file():
    raise FileNotFoundError(
        "Stage 2 KoBART decoder not found: expected "
        f"{STAGE2_DECODER_PATH} or {STAGE2_DECODER_FALLBACK_PATH}"
    )

try:
    from tokenizers import Tokenizer
except ImportError as exc:
    raise ImportError(
        "KoBART inference requires the 'tokenizers' package. "
        "Install it with: python -m pip install tokenizers"
    ) from exc

with open(VOCAB_PATH, "r", encoding="utf-8") as f:
    gloss_to_id = json.load(f)

id_to_gloss = {idx: g for g, idx in gloss_to_id.items()}

stage1_session = ort.InferenceSession(
    str(STAGE1_MODEL_PATH),
    providers=["CPUExecutionProvider"],
)
stage1_input_name = stage1_session.get_inputs()[0].name
stage1_output_name = stage1_session.get_outputs()[0].name
stage1_feature_width = stage1_session.get_inputs()[0].shape[-1]

stage2_encoder_session = ort.InferenceSession(
    str(STAGE2_ENCODER_PATH),
    providers=["CPUExecutionProvider"],
)
stage2_decoder_path = (
    STAGE2_DECODER_PATH
    if STAGE2_DECODER_PATH.is_file()
    else STAGE2_DECODER_FALLBACK_PATH
)
stage2_decoder_session = ort.InferenceSession(
    str(stage2_decoder_path),
    providers=["CPUExecutionProvider"],
)
kobart_tokenizer = Tokenizer.from_file(str(KOBART_TOKENIZER_PATH))
with open(KOBART_CONFIG_PATH, "r", encoding="utf-8") as f:
    kobart_config = json.load(f)
decoder_start_token_id = int(kobart_config["decoder_start_token_id"])
bos_token_id = int(kobart_config["bos_token_id"])
eos_token_id = int(kobart_config["eos_token_id"])


# --- 3. MEDIAPIPE LANDMARK EXTRACTION ---
def extract_video_landmarks(video_path, preview_count=5, frame_output_dir=None):
    """
    Reads a video and extracts 123 landmarks per frame: 11 pose, 70 face,
    and 21 per hand. The last dimension is [x, y, confidence/visibility].
    """
    mp_holistic = mp.solutions.holistic
    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        raise RuntimeError(f"Could not open video: {video_path}")
    
    frame_landmarks = []
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    preview_indices = set()
    if frame_output_dir is not None and preview_count > 0 and total_frames > 0:
        preview_indices = set(
            np.linspace(
                0,
                total_frames - 1,
                min(preview_count, total_frames),
                dtype=int,
            ).tolist()
        )
        frame_output_dir.mkdir(parents=True, exist_ok=True)

    frame_index = 0
    try:
        with mp_holistic.Holistic(
            static_image_mode=False,
            model_complexity=2,
            refine_face_landmarks=True,
            min_detection_confidence=0.5,
            min_tracking_confidence=0.5
        ) as holistic:
            while True:
                ret, frame = cap.read()
                if not ret:
                    break
                frame_index += 1

                image_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                results = holistic.process(image_rgb)

                pose_kps = [[0.0, 0.0, 0.0] for _ in range(11)]
                if results.pose_landmarks:
                    landmarks = results.pose_landmarks.landmark
                    for output_idx, source_idx in (
                        (0, 0),
                        (2, 12),
                        (3, 14),
                        (4, 16),
                        (5, 11),
                        (6, 13),
                        (7, 15),
                        (9, 24),
                        (10, 23),
                    ):
                        lm = landmarks[source_idx]
                        pose_kps[output_idx] = [lm.x, lm.y, lm.visibility]

                    for derived_idx, first_idx, second_idx in ((1, 11, 12), (8, 23, 24)):
                        first = landmarks[first_idx]
                        second = landmarks[second_idx]
                        pose_kps[derived_idx] = [
                            (first.x + second.x) / 2.0,
                            (first.y + second.y) / 2.0,
                            (first.visibility + second.visibility) / 2.0,
                        ]

                face_kps = []
                if results.face_landmarks:
                    face_landmarks = results.face_landmarks.landmark
                    face_indices = (
                        FACE_CHIN_INDICES
                        + FACE_RIGHT_EYEBROW_INDICES
                        + FACE_LEFT_EYEBROW_INDICES
                        + FACE_NOSE_INDICES
                        + FACE_RIGHT_PUPIL_INDICES
                        + FACE_LEFT_PUPIL_INDICES
                        + FACE_LIP_INDICES
                    )
                    face_kps = [
                        [lm.x, lm.y, 1.0]
                        for lm in (face_landmarks[index] for index in face_indices)
                    ]
                    for first_index, second_index in (
                        FACE_RIGHT_EYE_CORNERS,
                        FACE_LEFT_EYE_CORNERS,
                    ):
                        first = face_landmarks[first_index]
                        second = face_landmarks[second_index]
                        face_kps.append(
                            [
                                (first.x + second.x) / 2.0,
                                (first.y + second.y) / 2.0,
                                1.0,
                            ]
                        )
                face_kps.extend([[0.0, 0.0, 0.0]] * (70 - len(face_kps)))

                r_hand_kps = []
                if results.right_hand_landmarks:
                    r_hand_kps = [
                        [lm.x, lm.y, 1.0]
                        for lm in results.right_hand_landmarks.landmark
                    ]
                r_hand_kps.extend([[0.0, 0.0, 0.0]] * (21 - len(r_hand_kps)))

                l_hand_kps = []
                if results.left_hand_landmarks:
                    l_hand_kps = [
                        [lm.x, lm.y, 1.0]
                        for lm in results.left_hand_landmarks.landmark
                    ]
                l_hand_kps.extend([[0.0, 0.0, 0.0]] * (21 - len(l_hand_kps)))

                combined = np.array(
                    pose_kps + face_kps + l_hand_kps + r_hand_kps,
                    dtype=np.float32,
                )
                frame_landmarks.append(combined)

                if frame_index - 1 in preview_indices:
                    print(f"\nMediaPipe coordinates - frame {frame_index}:")
                    groups = [
                        ("pose", combined[:11], POSE_NAMES),
                        ("face", combined[11:81], None),
                        ("left hand", combined[81:102], None),
                        ("right hand", combined[102:123], None),
                    ]
                    for group_name, landmarks, names in groups:
                        print(f"  {group_name}:")
                        for landmark_index, (x, y, confidence) in enumerate(landmarks):
                            label = (
                                names[landmark_index]
                                if names is not None
                                else str(landmark_index)
                            )
                            print(
                                f"    {label}: x={x:.4f}, y={y:.4f}, "
                                f"visibility/confidence={confidence:.4f}"
                            )

                    annotated = frame.copy()
                    drawing = mp.solutions.drawing_utils
                    drawing.draw_landmarks(
                        annotated,
                        results.pose_landmarks,
                        mp_holistic.POSE_CONNECTIONS,
                    )
                    drawing.draw_landmarks(
                        annotated,
                        results.face_landmarks,
                        mp_holistic.FACEMESH_CONTOURS,
                    )
                    drawing.draw_landmarks(
                        annotated,
                        results.left_hand_landmarks,
                        mp_holistic.HAND_CONNECTIONS,
                    )
                    drawing.draw_landmarks(
                        annotated,
                        results.right_hand_landmarks,
                        mp_holistic.HAND_CONNECTIONS,
                    )
                    overlay_rows = []
                    for landmark_index, (x, y, confidence) in enumerate(combined[:11]):
                        overlay_rows.append(
                            f"Pose {POSE_NAMES[landmark_index]}: "
                            f"x={x:.3f} y={y:.3f} c={confidence:.2f}"
                        )
                    hand_labels = {
                        0: "wrist",
                        4: "thumb_tip",
                        8: "index_tip",
                        12: "middle_tip",
                        16: "ring_tip",
                        20: "pinky_tip",
                    }
                    for hand_name, hand_start in (("L", 81), ("R", 102)):
                        for landmark_index, landmark_name in hand_labels.items():
                            x, y, confidence = combined[hand_start + landmark_index]
                            overlay_rows.append(
                                f"{hand_name} {landmark_name}: "
                                f"x={x:.3f} y={y:.3f} c={confidence:.2f}"
                            )

                    panel_width = 330
                    panel_height = max(
                        annotated.shape[0],
                        44 + 20 * len(overlay_rows),
                    )
                    preview = np.zeros(
                        (panel_height, annotated.shape[1] + panel_width, 3),
                        dtype=np.uint8,
                    )
                    preview[:annotated.shape[0], :annotated.shape[1]] = annotated
                    cv2.putText(
                        preview,
                        "MediaPipe normalized image x, y",
                        (annotated.shape[1] + 10, 25),
                        cv2.FONT_HERSHEY_SIMPLEX,
                        0.48,
                        (255, 255, 255),
                        1,
                    )
                    for row_index, row in enumerate(overlay_rows):
                        cv2.putText(
                            preview,
                            row,
                            (annotated.shape[1] + 10, 48 + 20 * row_index),
                            cv2.FONT_HERSHEY_SIMPLEX,
                            0.42,
                            (100, 255, 100),
                            1,
                        )
                    cv2.putText(
                        preview,
                        f"Frame {frame_index}",
                        (10, 30),
                        cv2.FONT_HERSHEY_SIMPLEX,
                        0.65,
                        (0, 255, 0),
                        2,
                    )
                    output_path = frame_output_dir / f"frame_{frame_index:06d}.jpg"
                    if not cv2.imwrite(str(output_path), preview):
                        raise RuntimeError(f"Could not write preview frame: {output_path}")
                    print(f"  Annotated frame saved to: {output_path}")
    finally:
        cap.release()

    return np.array(frame_landmarks)  # Shape: (num_frames, 123, 3)


# --- 4. PREPROCESSING & NORMALIZATION ---
def preprocess_video_features(raw_kps):
    """
    Normalizes each frame around its shoulder center and width, then computes
    velocities from the normalized coordinates in PDF group order.
    Returns model features as (1, num_frames, landmarks * 4).
    """
    num_frames, _, _ = raw_kps.shape
    xy = raw_kps[:, :, :2].copy()

    # The NIA features place the shoulders at approximately x=-0.5 and x=+0.5
    # in each frame, so normalize using each frame's shoulder width.
    r_shoulder = xy[:, R_SHOULDER_IDX, :]
    l_shoulder = xy[:, L_SHOULDER_IDX, :]
    shoulder_center = (r_shoulder + l_shoulder) / 2.0
    shoulder_dist = np.linalg.norm(r_shoulder - l_shoulder, axis=1)
    xy -= shoulder_center[:, None, :]
    scale = np.where(shoulder_dist > 1e-6, shoulder_dist, 1.0)
    xy /= scale[:, None, None]

    # Compute frame-by-frame velocity (dx, dy)
    velocity = np.zeros_like(xy)
    if num_frames > 1:
        velocity[1:] = xy[1:] - xy[:-1]

    # Concatenate [x, y, dx, dy] -> (num_frames, landmarks, 4)
    features = np.concatenate([xy, velocity], axis=2)
    
    # Flatten landmarks to (num_frames, landmarks * 4)
    flattened_features = features.reshape(num_frames, -1)
    
    return np.expand_dims(flattened_features.astype(np.float32), axis=0)


# --- 5. DECODING & INFERENCE ---
def decode_gloss_sequence(logits, id_to_gloss, threshold=0.3):
    """
    Groups consecutive frame predictions into a sequence of non-repeating gloss words.
    """
    logits = logits[0]
    shifted_logits = logits - np.max(logits, axis=-1, keepdims=True)
    exp_logits = np.exp(shifted_logits)
    probs = exp_logits / np.sum(exp_logits, axis=-1, keepdims=True)
    max_probs = np.max(probs, axis=-1)
    preds = np.argmax(probs, axis=-1)

    seq = []
    prev = -1
    for idx, prob in zip(preds, max_probs):

        if prob < threshold or idx == 0:  # Treat background and low confidence as a boundary
            prev = 0
            continue

        if idx != prev:
            gloss_word = id_to_gloss.get(idx, "")
            if gloss_word:
                seq.append(gloss_word)
            prev = idx

    return " ".join(seq)


def generate_korean_sentence(gloss_sequence, max_length=48):
    """Translate a predicted gloss sequence using the exported KoBART ONNX models."""
    if not gloss_sequence.strip():
        return ""
    if max_length < 2:
        raise ValueError("max_length must be at least 2")

    encoded_glosses = kobart_tokenizer.encode(
        gloss_sequence,
        add_special_tokens=False,
    )
    input_ids = np.array(
        [[bos_token_id, *encoded_glosses.ids, eos_token_id]],
        dtype=np.int64,
    )
    attention_mask = np.ones_like(input_ids)
    encoder_hidden_states = stage2_encoder_session.run(
        ["last_hidden_state"],
        {
            "input_ids": input_ids,
            "attention_mask": attention_mask,
        },
    )[0]

    generated_ids = [decoder_start_token_id]
    for _ in range(max_length - 1):
        # This export fails for a one-token decoder input. The first-position
        # logits remain causal, so a second start token can safely pad that call.
        if len(generated_ids) == 1:
            decoder_input_ids = [decoder_start_token_id, decoder_start_token_id]
            output_index = 0
        else:
            decoder_input_ids = generated_ids
            output_index = -1

        logits = stage2_decoder_session.run(
            ["logits"],
            {
                "decoder_input_ids": np.array(
                    [decoder_input_ids],
                    dtype=np.int64,
                ),
                "encoder_hidden_states": encoder_hidden_states,
                "encoder_attention_mask": attention_mask,
            },
        )[0][0, output_index].copy()

        for token_id in set(generated_ids[1:]):
            if logits[token_id] < 0:
                logits[token_id] *= 1.3
            else:
                logits[token_id] /= 1.3

        if len(generated_ids) >= 2:
            previous_ngram_prefix = tuple(generated_ids[-2:])
            banned_tokens = {
                generated_ids[index + 2]
                for index in range(len(generated_ids) - 2)
                if tuple(generated_ids[index:index + 2]) == previous_ngram_prefix
            }
            if banned_tokens:
                logits[list(banned_tokens)] = -np.inf

        next_token_id = int(np.argmax(logits))
        if next_token_id == eos_token_id:
            break
        generated_ids.append(next_token_id)

    return kobart_tokenizer.decode(
        generated_ids[1:],
        skip_special_tokens=True,
    ).strip()


def predict_glosses(
    video_path,
    preview_count=5,
    frame_output_dir=None,
    keypoints_output=None,
    max_sentence_tokens=48,
):
    video_path = Path(video_path)
    if keypoints_output is None:
        keypoints_output = video_path.with_name(
            f"{video_path.stem}_keypoints.npy"
        )
    else:
        keypoints_output = Path(keypoints_output)

    print(f"\nProcessing video: {video_path}")
    
    # 1. Extract raw landmarks
    raw_kps = extract_video_landmarks(
        video_path,
        preview_count=preview_count,
        frame_output_dir=frame_output_dir,
    )
    if len(raw_kps) == 0:
        raise RuntimeError(f"No frames found in video: {video_path}")

    # 2. Preprocess to model feature format
    input_features = preprocess_video_features(raw_kps)
    keypoints_output.parent.mkdir(parents=True, exist_ok=True)
    comparable_keypoints = input_features[0].reshape(
        len(raw_kps), raw_kps.shape[1], 4
    ).astype(np.float32)
    np.save(keypoints_output, comparable_keypoints)
    print(f"Model-ready keypoints saved to: {keypoints_output}")

    # The ONNX model uses the older right-hand-before-left-hand convention.
    # Export in PDF order, but reorder hands for this model at inference time.
    inference_features = input_features
    if stage1_feature_width == LEGACY_FEATURE_WIDTH and raw_kps.shape[1] == 123:
        keypoints = input_features[0].reshape(
            len(raw_kps), 123, 4
        )
        model_order_keypoints = np.concatenate(
            (keypoints[:, :81], keypoints[:, 102:123], keypoints[:, 81:102]),
            axis=1,
        )
        inference_features = model_order_keypoints.reshape(
            1, len(model_order_keypoints), LEGACY_FEATURE_WIDTH
        )
    elif (
        isinstance(stage1_feature_width, int)
        and input_features.shape[-1] != stage1_feature_width
    ):
        raise ValueError(
            f"ONNX model expects {stage1_feature_width} features per frame, "
            f"but extracted keypoints provide {input_features.shape[-1]}"
        )

    # 3. Stage 1 Inference: Keypoints -> Predicted Gloss Sequence
    s1_logits = stage1_session.run(
        [stage1_output_name],
        {stage1_input_name: inference_features},
    )[0]
    pred_gloss_string = decode_gloss_sequence(s1_logits, id_to_gloss)
    pred_sentence = generate_korean_sentence(
        pred_gloss_string,
        max_length=max_sentence_tokens,
    )

    print(f" Predicted Glosses: '{pred_gloss_string}'")
    if not pred_gloss_string.strip():
        print("No sign gestures recognized in the video.")
    print(f" Predicted Korean Sentence: '{pred_sentence or '(none)'}'")
    return pred_gloss_string


# --- 5. EXECUTE ---
if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Predict glosses and save sampled video frames with MediaPipe landmarks."
    )
    parser.add_argument(
        "video",
        nargs="?",
        type=Path,
        default=PROJECT_DIR / "sample_test_sign.mp4",
        help="Video file to process (defaults to sample_test_sign.mp4)",
    )
    parser.add_argument(
        "--preview-count",
        type=int,
        default=5,
        help="Number of evenly spaced annotated frames to save (default: 5)",
    )
    parser.add_argument(
        "--frame-output-dir",
        type=Path,
        default=PROJECT_DIR / "mediapipe_frames",
        help="Folder for annotated preview images",
    )
    parser.add_argument(
        "--save-keypoints",
        type=Path,
        default=None,
        help=(
            "Save keypoints to this .npy path "
            "(default: <video name>_keypoints.npy beside the video)"
        ),
    )
    parser.add_argument(
        "--max-sentence-tokens",
        type=int,
        default=48,
        help="Maximum KoBART output length, including its start token (default: 48).",
    )
    args = parser.parse_args()
    if args.preview_count < 0:
        parser.error("--preview-count must be zero or greater")
    if args.max_sentence_tokens < 2:
        parser.error("--max-sentence-tokens must be at least 2")
    predict_glosses(
        args.video,
        preview_count=args.preview_count,
        frame_output_dir=args.frame_output_dir,
        keypoints_output=args.save_keypoints,
        max_sentence_tokens=args.max_sentence_tokens,
    )