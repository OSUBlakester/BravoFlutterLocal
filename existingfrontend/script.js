const startScanningButton = document.getElementById('startScanningButton');
const grid = document.getElementById('scanningGrid');
const buttons = grid.querySelectorAll('button');
const llmResponses = document.getElementById('llmResponses');

let currentIndex = 0;
let scanningSpeed = 2000;
let listeningForQuestion = false;
let isSpeaking = false;
let utteranceQueue = []; // Queue for utterances
let scanningActive = false; // Add a flag to track scanning state
let buttoncount = buttons.length
let originalprompt = ""
let originalresults = ""

// Speech Recognition Setup
const recognition = new (window.SpeechRecognition || window.webkitSpeechRecognition)();
recognition.continuous = true;
recognition.interimResults = false;

recognition.onresult = async (event) => {
  const transcript = event.results[event.results.length - 1][0].transcript.toLowerCase();
  console.log('Speech recognized:', transcript); // Debugging log

  if (!listeningForQuestion) {
    if (transcript.includes('hey brady')) {
        stopScanning();
        speak('Listening...');
        listeningForQuestion = true;
    }
} else {
    listeningForQuestion = false;
    recognition.stop();
    llmResponses.innerHTML = 'Generating...';
    try {
      originalprompt = transcript
      const response = await getLLMResponse(transcript);
      llmResponses.innerHTML = response.replace(/\n/g, '<br>');
      speak("Here are some options");
      setTimeout(startScanning, 2000);
    } catch (error) {
      console.error('Error getting LLM response:', error);
      llmResponses.innerHTML = 'Error generating response.';
      setTimeout(startScanning, 2000);
    }
  }
};

recognition.onerror = (event) => {
  console.error('Speech recognition error:', event.error);
};

recognition.onend = () => {
    if (listeningForQuestion === false){
        recognition.start(); // restart listening.
    }
};

function highlightOption(index) {
  buttons.forEach((button, i) => {
    button.classList.remove('highlighted');
    if (i === index) {
      button.classList.add('highlighted');
    }
  });
}

function enqueueUtterance(text) {
  utteranceQueue.push({text, index: currentIndex}); // Enqueue utterance with index
  // console.log("Utterance Enqueued:", {text, index: currentIndex});
  if (!isSpeaking) {
    processUtteranceQueue();
  }
}

function processUtteranceQueue() {
  if (utteranceQueue.length > 0) {
    isSpeaking = true;
    const utteranceData = utteranceQueue.shift();
 //   console.log("Processing Utterance:", utteranceData);
    const utterance = new SpeechSynthesisUtterance(utteranceData.text);
    highlightOption(utteranceData.index); // Highlight current index

    utterance.onend = () => {
      isSpeaking = false;
      currentIndex = (utteranceData.index + 1) % buttons.length; // Increment index from the utterance index
 //     console.log("Utterance Ended, Next Index:", currentIndex);
      if (utteranceQueue.length > 0) {
        processUtteranceQueue(); // Process next utterance in queue
      } else if (scanningActive) { // Check scanningActive here
//        console.log("Utterance Queue Empty, Triggering Next Utterance");
        speak(buttons[currentIndex].dataset.option); // Trigger next utterance
      } else {
 //       console.log("Utterance Queue Empty");
      }
    };
    window.speechSynthesis.speak(utterance);
  }
}

function speak(text) {
    enqueueUtterance(text);
}

function startScanning() {
  if (!scanningActive) { // Only start if not already active
      scanningActive = true;
      currentIndex = 0;
//      console.log("Start Scanning, Index:", currentIndex);
      speak(buttons[currentIndex].dataset.option); //start the first prompt.
  }
}

function stopScanning() {
  utteranceQueue = [];
  isSpeaking = false;
  scanningActive = false; //reset the scanning state
  console.log("Scanning Stopped");
}

recognition.start(); // Start speech recognition



let standardButtonOptions = [];

async function loadStandardOptions() {
    try {
        const response = await fetch('options.json');
        standardButtonOptions = await response.json();
        updateButtonsWithStandardOptions();
    } catch (error) {
        console.error('Error loading standard options:', error);
    }
}

function updateButtonsWithStandardOptions() {
    buttons.forEach((button, index) => {
        if (standardButtonOptions[index]) {
            button.dataset.option = standardButtonOptions[index].option;
            button.innerHTML = standardButtonOptions[index].text;
        }
    });
    storeOriginalButtonOptions();
}



let originalButtonOptions = []; // Store original button options

function storeOriginalButtonOptions() {
    originalButtonOptions = Array.from(buttons).map(button => ({
        option: button.dataset.option,
        text: button.innerHTML
    }));
}

function restoreOriginalButtonOptions() {
    buttons.forEach((button, index) => {
        if (originalButtonOptions[index]) {
            button.dataset.option = originalButtonOptions[index].option;
            button.innerHTML = originalButtonOptions[index].text;
        }
    });
}


buttons.forEach(button => {
  button.addEventListener('click', () => {
      stopScanning();
      if (button.dataset.option === "Something Else") {
          let revisedPrompt = originalprompt + " excluding these items: " + originalresults;
          getLLMResponse(revisedPrompt);
      } else if (button.dataset.option === "Please ask me again") {
          listeningForQuestion = true;
          speak("Listening...");
          recognition.start();
      } else {
          speak(button.dataset.option);
          restoreOriginalButtonOptions();
          setTimeout(startScanning, 2000);
      }
  });
});


async function getLLMResponse(prompt) {
  try {
    storeOriginalButtonOptions() // Store original options before updating buttons
    const refinedPrompt = `Provide 3-5 short, single-phrase options for the following question: "${prompt}".`;
    console.log("Sending LLM Request:", refinedPrompt);
    const response = await fetch('/llm', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ prompt: refinedPrompt }),
    });

    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`);
    }

    const data = await response.text();
    console.log("LLM Response Received (Raw):", data);

    // Parse the LLM response

    // remove "1. from beginning 
    //const datatrim1 = data.substring(4,data.length-5)

    //remove last quote
    //const datatrim2 = datatrim1.substring(0,datatrim1.length-1)

    //console.log("trimmed front and end:", datatrim2);

    originalresults = data

    const options = data
      .split("\\n")
      .map((option) => option.replace(/^\d+\.\s*/, '').trim()) // Remove numbering and trim
      .filter((option) => option !== "");

  

    // Update button labels
    buttons.forEach((button, index) => {
      if (index < (buttoncount - 2)) {
        let optionbefore = options[index];
        let optionafter = optionbefore.replace(/\\/g, '');
        let optionafter2 = optionafter.replace(/['"]+/g, '');
        let optionafter3 = optionafter2.replace(/^\d+\.\s*/, '');

        console.log("option before: ", optionbefore);
        console.log("option after: ", optionafter3);
        
        if (options[index]) {
          button.dataset.option = optionafter3;
          button.innerHTML = optionafter3;
        } else {
          button.dataset.option = "";
          button.innerHTML = "";
        }
      }
      else {
        if (index < buttoncount-1) {
          button.dataset.option = "Something Else";
          button.innerHTML = "Something Else";
        }
        else {
          button.dataset.option = "Please ask me again";
          button.innerHTML = "Please ask me again";
             }  
            }
          }
    );



    // Restart scanning
    speak("Here are some options");
    setTimeout(startScanning, 2000);

    return data;
  } catch (error) {
    console.error("Error fetching LLM Response:", error);
    throw error;
  }
}


startScanningButton.addEventListener('click', () => {
  startScanning();
  startScanningButton.style.display = "none";
  grid.style.display = "grid";
});

 // console.log("Voices:", window.speechSynthesis.getVoices());