import sys
import json
import os

def replace_in_file(project_root, path, old, new):
    full_path = os.path.join(project_root, path)
    if not os.path.exists(full_path):
        print(f"Warning: File {full_path} not found")
        return
    with open(full_path, 'r') as f: content = f.read()
    print(f"Replacing '{old}' with '{new}' in {full_path}")
    new_content = content.replace(old, new)
    with open(full_path, 'w') as f: f.write(new_content)

def main():
    print("Starting manifest patching...")
    env = sys.argv[1] if len(sys.argv) > 1 else 'dev'
    project_root = sys.argv[2] if len(sys.argv) > 2 else '.'
    
    raw_input = sys.stdin.read()
    start_idx = raw_input.find('{')
    if start_idx == -1:
        print("No JSON found in input")
        print(f"Input was: {raw_input[:100]}...")
        sys.exit(1)
    
    try:
        outputs = json.loads(raw_input[start_idx:])
    except Exception as e:
        print(f"JSON Parse Error: {e}")
        sys.exit(1)
    
    print(f"Keys available: {list(outputs.keys())}")
    
    acr_server = outputs.get('acr_login_server', {}).get('value')
    kv_name = outputs.get('key_vault_name', {}).get('value')
    tenant_id = outputs.get('tenant_id', {}).get('value')
    
    env = sys.argv[1] if len(sys.argv) > 1 else 'dev'
    
    if acr_server:
        replace_in_file(project_root, f'k8s/overlays/{env}/kustomization.yaml', 'acrcloudplatformdev.azurecr.io', acr_server)
    else:
        print("Missing acr_login_server")
        
    if kv_name:
        replace_in_file(project_root, f'k8s/overlays/{env}/secret-provider-patch.yaml', 'kv-cloudplatform-dev', kv_name)
    else:
        print("Missing key_vault_name")
        
    if tenant_id:
        replace_in_file(project_root, f'k8s/overlays/{env}/secret-provider-patch.yaml', 'REPLACE_WITH_YOUR_TENANT_ID', tenant_id)
    else:
        print("Missing tenant_id")

if __name__ == "__main__":
    main()
