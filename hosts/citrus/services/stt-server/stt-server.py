import json
import os
import shutil
import subprocess
import tempfile
import threading
from pathlib import Path

import uvicorn
from fastapi import FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.responses import JSONResponse, PlainTextResponse

PORT = int(os.environ["STT_PORT"])
MODEL_DIR = os.environ["STT_MODEL_DIR"]
MODEL_IDS = ("whisper-1", "large-v3")
TEXT_FORMATS = {"text": "txt", "srt": "srt", "vtt": "vtt"}
JSON_FORMATS = ("json", "verbose_json")

gpu = threading.Lock()
app = FastAPI()


@app.exception_handler(HTTPException)
def openai_error(_: Request, error: HTTPException):
    return JSONResponse(status_code=error.status_code, content={"error": {"message": str(error.detail), "type": "invalid_request_error" if error.status_code < 500 else "server_error"}})


def run(command):
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode:
        raise HTTPException(500, result.stderr[-2000:] or "transcription failed")
    return result.stdout.strip()


def whisper(audio, work, language, prompt, temperature, words):
    command = [
        "whisper-ctranslate2", str(audio),
        "--model", "large-v3",
        "--model_dir", MODEL_DIR,
        "--device", "cuda",
        "--compute_type", "float16",
        "--task", "transcribe",
        "--vad_filter", "True",
        "--verbose", "False",
        "--output_format", "all",
        "--output_dir", str(work),
    ]
    if language:
        command += ["--language", language]
    if prompt:
        command += ["--initial_prompt", prompt]
    if temperature is not None:
        command += ["--temperature", str(temperature)]
    if words:
        command += ["--word_timestamps", "True"]
    run(command)
    if not (work / f"{audio.stem}.json").is_file():
        raise HTTPException(500, "transcription produced no output")


def verbose(result, words):
    segments = result["segments"]
    response = {
        "task": "transcribe",
        "language": result["language"],
        "duration": segments[-1]["end"] if segments else 0.0,
        "text": result["text"],
        "segments": segments,
    }
    if words:
        response["words"] = [word for segment in segments for word in segment.get("words", [])]
    return response


@app.get("/v1/models")
def models():
    return {"object": "list", "data": [{"id": model, "object": "model", "owned_by": "citrus"} for model in MODEL_IDS]}


@app.post("/v1/audio/transcriptions")
def transcriptions(
    file: UploadFile = File(...),
    model: str = Form("whisper-1"),
    language: str | None = Form(None),
    prompt: str | None = Form(None),
    response_format: str = Form("json"),
    temperature: float | None = Form(None),
    timestamp_granularities: list[str] = Form([], alias="timestamp_granularities[]"),
    denoise: bool = Form(True),
):
    if response_format not in (*JSON_FORMATS, *TEXT_FORMATS):
        raise HTTPException(400, f"unsupported response_format: {response_format}")
    words = "word" in timestamp_granularities
    with tempfile.TemporaryDirectory() as directory:
        work = Path(directory)
        audio = work / f"input{Path(file.filename or '').suffix}"
        with audio.open("wb") as output:
            shutil.copyfileobj(file.file, output)
        with gpu:
            if denoise:
                audio = Path(run(["reuse-denoise", str(audio), str(work / "denoised")]))
            whisper(audio, work, language, prompt, temperature, words)
        if response_format in TEXT_FORMATS:
            path = work / f"{audio.stem}.{TEXT_FORMATS[response_format]}"
            return PlainTextResponse(path.read_text())
        result = json.loads((work / f"{audio.stem}.json").read_text())
    if response_format == "verbose_json":
        return verbose(result, words)
    return {"text": result["text"]}


uvicorn.run(app, host="127.0.0.1", port=PORT)
