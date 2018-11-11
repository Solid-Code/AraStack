pragma solidity ^0.4.25;

import "@daostack/infra/contracts/votingMachines/IntVoteInterface.sol";
import "@daostack/infra/contracts/votingMachines/VotingMachineCallbacksInterface.sol";
import "./UniversalScheme.sol";
import "../votingMachines/VotingMachineCallbacks.sol";


/**
 * @title AragonScheme.
 * @dev  A scheme for proposing and executing calls to an arbitrary function
 * on a specific contract on behalf of the organization avatar.
 */
contract AragonScheme is UniversalScheme,VotingMachineCallbacks,ProposalExecuteInterface {
    //note 
    bytes4 public constant ARAGON_KERNEL_HAS_PERMISSION = 0xfdef9106;
    
    event NewCallProposal(
        address indexed _avatar,
        bytes32 indexed _proposalId,
        bytes   callData,
        bytes32 nameSpace,
        bytes32 appId
    );
    
    event ProposalExecuted(address indexed _avatar, bytes32 indexed _proposalId,int _param);
    event ProposalDeleted(address indexed _avatar, bytes32 indexed _proposalId);
    event AddressGotten(bytes32 _nameSpace, bytes32 _appID, address _appAddress);

    // Details of a voting proposal:
    struct CallProposal {
        bytes callData;
        bytes32 nameSpace;
        bytes32 appId;
        bool exist;
    }

    // A mapping from the organization (Avatar) address to the saved data of the organization:
    mapping(address=>mapping(bytes32=>CallProposal)) public organizationsProposals;

    struct Parameters {
        IntVoteInterface intVote;
        bytes32 voteParams;
        address aragonKernel;
    }

    // A mapping from hashes to parameters (use to store a particular configuration on the controller)
    mapping(bytes32=>Parameters) public parameters;

    /**
    * @dev execution of proposals, can only be called by the voting machine in which the vote is held.
    * @param _proposalId the ID of the voting in the voting machine
    * @param _param a parameter of the voting result, 1 yes and 2 is no.
    */
    function executeProposal(bytes32 _proposalId,int _param) external onlyVotingMachine(_proposalId) returns(bool) {
        address avatar = proposalsInfo[_proposalId].avatar;
        Parameters memory params = parameters[getParametersFromController(Avatar(avatar))];

        // Save proposal to memory and delete from storage:
        CallProposal memory proposal = organizationsProposals[avatar][_proposalId];
        require(proposal.exist,"must be a live proposal");
        delete organizationsProposals[avatar][_proposalId];
        emit ProposalDeleted(avatar, _proposalId);

        address contractToCall = AragonKernel(params.aragonKernel).getApp(proposal.nameSpace, proposal.appId);

        bool retVal = true;
        // If no decision do nothing:
        if (_param != 0) {
        // Define controller and get the params:
            ControllerInterface controller = ControllerInterface(Avatar(avatar).owner());
            if (controller.genericCall(
                     contractToCall,
                     proposal.callData,
                     avatar) == bytes32(0)) {
                retVal = false;
            }
          }
        emit ProposalExecuted(avatar, _proposalId,_param);
        return retVal;
    }

    /**
    * @dev Hash the parameters, save them if necessary, and return the hash value
    * @param _voteParams -  voting parameters
    * @param _intVote  - voting machine contract.
    * @return bytes32 -the parameters hash
    */
    function setParameters(
        bytes32 _voteParams,
        IntVoteInterface _intVote,
        address _aragonKernel
    ) public returns(bytes32)
    {
        bytes32 paramsHash = getParametersHash(_voteParams, _intVote,_aragonKernel);
        parameters[paramsHash].voteParams = _voteParams;
        parameters[paramsHash].intVote = _intVote;
        parameters[paramsHash].aragonKernel = _aragonKernel;
        return paramsHash;
    }

    /**
    * @dev Hash the parameters, and return the hash value
    * @param _voteParams -  voting parameters
    * @param _intVote  - voting machine contract.
    * @return bytes32 -the parameters hash
    */
    function getParametersHash(
        bytes32 _voteParams,
        IntVoteInterface _intVote,
        address _aragonKernel
    ) public pure returns(bytes32)
    {
        return keccak256(abi.encodePacked(_voteParams, _intVote, _aragonKernel));
    }

    /**
    * @dev propose to call on behalf of the _avatar
    *      The function trigger NewCallProposal event
    * @param _callData - The abi encode data for the call
    * @param _avatar avatar of the organization
    * @return an id which represents the proposal
    */
    function proposeAragonCall(Avatar _avatar, bytes _callData, bytes32 _nameSpace, bytes32 _appId)
    public
    returns(bytes32)
    {
        Parameters memory params = parameters[getParametersFromController(_avatar)];

        address where = AragonKernel(params.aragonKernel).getApp(_nameSpace, _appId);
        require(where != 0, "invalid app");
        
/*
        bytes memory hasPermissionCallData = abi.encodePacked(
            ARAGON_KERNEL_HAS_PERMISSION,
            msg.sender,
            where,
            keccak256("INCREMENT_ROLE"),
            uint256(0)
        );

        ControllerInterface controller = ControllerInterface(Avatar(_avatar).owner());
       
        controller.genericCall(
            params.aragonKernel,
            hasPermissionCallData,
            _avatar);
*/
        IntVoteInterface intVote = params.intVote;

        bytes32 proposalId = intVote.propose(2, params.voteParams,msg.sender,_avatar);

        organizationsProposals[_avatar][proposalId] = CallProposal({
            callData: _callData,
            nameSpace: _nameSpace,
            appId: _appId,
            exist: true
        });

        proposalsInfo[proposalId] = ProposalInfo(
            {blockNumber:block.number,
            avatar:_avatar,
            votingMachine:params.intVote});
        emit NewCallProposal(_avatar,proposalId,_callData,_nameSpace,_appId);
        emit AddressGotten(_nameSpace, _appId, where);
        return proposalId;
    }
}

interface AragonKernel{
    //function hasPermission(address _who, address _where, bytes32 _what, bytes _how) external view returns (bool);
    function getApp(bytes32 _namespace, bytes32 _appId) external view returns (address);
}