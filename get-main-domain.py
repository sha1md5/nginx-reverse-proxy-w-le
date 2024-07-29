import sys
import tldextract

def get_main_domain(domain):
    extracted = tldextract.extract(domain)
    main_domain = f"{extracted.domain}.{extracted.suffix}"
    return main_domain

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python script.py <domain>")
        sys.exit(1)

    input_domain = sys.argv[1]
    main_domain = get_main_domain(input_domain)
    print(main_domain)