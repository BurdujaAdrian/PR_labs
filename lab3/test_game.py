import threading
import requests
import random
import subprocess

def send_request(round):
    for i in range(0,100):
        random.seed(((round * 191288518)+i)%12412415)
        url =  "http://localhost:8080/flip/"
        url += "thread"+str(round)+"/"
        url += str(random.randrange(1,3))
        url += ","
        url += str(random.randrange(1,6))
        print(f"Sending {url} from Thread{threading.current_thread().name}",flush=True)
        response = requests.get(url)
        print(f"Thread {threading.current_thread().name}: {url} -> Status: {response.status_code}",flush=True)

def main():
    # List of URLs to request


    threads = []
    for round in range(0,4):
            thread = threading.Thread(target=send_request, args=(round,))
            threads.append(thread)
            thread.start()
            print(f"Started {thread.name}")
        
    for thread in threads:
        thread.join()

    
    print("All requests completed!")

if __name__ == "__main__":
    main()
